import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Math;
import Toybox.Time.Gregorian;
import Toybox.Application.Properties;
import Toybox.WatchUi;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.UserProfile;
import Toybox.Position;
import Toybox.SensorHistory;

// Base greys
var COLOR_LABEL = Graphics.createColor(255, 0x99, 0x99, 0x99); // #999999
var COLOR_YEAR  = Graphics.createColor(255, 0xaa, 0xaa, 0xaa); // #aaaaaa
var COLOR_MONTH = Graphics.createColor(255, 0xcc, 0xcc, 0xcc); // #cccccc

// Fitbit-style accent colours
var COLOR_EPOCH = Graphics.createColor(255, 255, 0, 0);        // bright red
var COLOR_UTC   = Graphics.createColor(255,  80, 120, 255);    // blue
var COLOR_STEPS = Graphics.createColor(255,   0, 255, 0);      // green
var COLOR_BATT_FULL  = Graphics.createColor(255, 0, 128, 255); // blue-ish
var COLOR_BATT       = Graphics.createColor(255, 255, 255, 0); // yellow
var COLOR_BATT_LOW   = Graphics.createColor(255, 255, 0, 0);   // red

// Left X positions (tweak these to move everything in/out)
var STATS_LABEL_X = 54;   // labels: STP/CAL/DST/FLR/PRS/...
var STATS_VALUE_X = 156;  // values: numbers for those labels
var RIGHT_COL_X = 270;

// Battery label -> value pixel gap (only BAT uses measuring)
var BAT_LABEL_GAP = 8;

class ProgrammersWatchfaceView extends WatchUi.WatchFace {

    private var _lastPhoneConnectMoment;

    function initialize() {
        WatchFace.initialize();
        _lastPhoneConnectMoment = null;
    }

    function onLayout(dc as Dc) as Void {
        // Custom draw only; no XML layout for now
        // setLayout(Rez.Layouts.WatchFace(dc));
    }

    // ---------- helpers ----------

    private function _fmt2(n) {
        if (n < 10) {
            return "0" + n.toString();
        }
        return n.toString();
    }

    private function _fmt3(n) {
        if (n < 10) {
            return "00" + n.toString();
        } else if (n < 100) {
            return "0" + n.toString();
        }
        return n.toString();
    }

    private function _drawRightCol(dc as Dc, y, label, value, font, valueColor) {

        // Add a space between label and value as requested
        var labelStr = label + " ";

        var lw = dc.getTextWidthInPixels(labelStr, font);
        // RIGHT_COL_X acts as the start of the right-side label/value pair.
        var valueX = RIGHT_COL_X;
        // Draw label
        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(valueX, y, font, labelStr, Graphics.TEXT_JUSTIFY_LEFT);

        // Draw value
        dc.setColor(valueColor, Graphics.COLOR_BLACK);
        dc.drawText(valueX + lw, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // km with nearest 10m (0.01 km); no decimals unless needed
    private function _fmtKm(km) {
        // Clamp negative and tiny noise
        if (km <= 0) {
            return "0";
        }

        // scale to hundredths of a km and round
        var scaled = Math.round(km * 100.0).toLong(); // e.g. 1.23km -> 123

        var whole = scaled / 100;      // integer km
        var frac2 = scaled % 100;      // 0..99 (hundredths)

        if (frac2 == 0) {
            // exact km
            return whole.toString();
        }

        if (frac2 % 10 == 0) {
            // only one decimal needed (e.g. 1.20 -> 1.2)
            var oneDec = (frac2 / 10).toString();
            return whole.toString() + "." + oneDec;
        }

        // full two decimals, zero-padded if needed (e.g. 1.03)
        var fracStr = frac2.toString();
        if (frac2 < 10) {
            fracStr = "0" + fracStr;
        }
        return whole.toString() + "." + fracStr;
    }



    // Convert Gregorian.Info.day_of_week to 3-letter lowercase ("sun", "mon", ...)
    private function _dow3(dowVal) {
        if (dowVal == null) {
            return "";
        }

        if (dowVal instanceof Lang.String) {
            var s = dowVal;
            if (s.length() >= 3) {
                s = s.substring(0,3);
            }
            return s.toLower();
        }

        var names = [ "sun", "mon", "tue", "wed", "thu", "fri", "sat" ];
        var n = dowVal.toNumber();

        var idx = n - 1;
        if (idx < 0) {
            idx = n;
        }
        idx = idx % 7;
        if (idx < 0) {
            idx += 7;
        }

        return names[idx];
    }

    private function _isLeapYear(year) {
        if ((year % 4) != 0) {
            return false;
        }

        if ((year % 100) != 0) {
            return true;
        }

        return ((year % 400) == 0);
    }

    private function _dayOfYear(year, month, day) {
        var daysBeforeMonth = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
        var doy = daysBeforeMonth[month - 1] + day;

        if (_isLeapYear(year) && month > 2) {
            doy += 1;
        }

        return doy;
    }

    // Sakamoto weekday: 0=Sunday .. 6=Saturday
    private function _weekdaySunday0(year, month, day) {
        var offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
        var y = year;

        if (month < 3) {
            y -= 1;
        }

        var dow = y
            + Math.floor(y / 4.0).toLong()
            - Math.floor(y / 100.0).toLong()
            + Math.floor(y / 400.0).toLong()
            + offsets[month - 1]
            + day;

        return dow % 7;
    }

    // ISO weekday: Monday=1 .. Sunday=7
    private function _isoWeekday(year, month, day) {
        var dow = _weekdaySunday0(year, month, day);
        if (dow == 0) {
            return 7;
        }
        return dow;
    }

    private function _isoWeeksInYear(year) {
        var jan1IsoDow = _isoWeekday(year, 1, 1);

        if (jan1IsoDow == 4 || (jan1IsoDow == 3 && _isLeapYear(year))) {
            return 53;
        }

        return 52;
    }

    private function _isoWeekNumber(year, month, day) {
        var doy = _dayOfYear(year, month, day);
        var isoDow = _isoWeekday(year, month, day);
        var week = Math.floor(((doy - isoDow + 10).toFloat()) / 7.0).toLong();

        if (week < 1) {
            return _isoWeeksInYear(year - 1);
        }

        var weeksThisYear = _isoWeeksInYear(year);
        if (week > weeksThisYear) {
            return 1;
        }

        return week;
    }

    private function _drawLabelValueCenter(dc as Dc, cx, y, label, value, font) {
        var labelStr = label + " ";
        var labelW = dc.getTextWidthInPixels(labelStr, font);
        var valueW = dc.getTextWidthInPixels(value, font);
        var totalW = labelW + valueW;
        var xStart = cx - (totalW / 2);
    
        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(xStart, y, font, labelStr, Graphics.TEXT_JUSTIFY_LEFT);
    
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(xStart + labelW, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function _getLabels() {
        var mode = null;

        try {
            mode = Properties.getValue("LabelMode");
        } catch (ex) {
            mode = null;
        }

        var shortMode = (mode == 3);

        if (shortMode) {
            return {
                :stp => "STP",
                :cal => "CAL",
                :dst => "DST",
                :flr => "FLR",
                :prs => "PRS",
                :bat => "BAT",
                :syn => "SYN",
                :chg => "CHG",
                :alt => "ALT",
                :bdb => "BBT",
                :vo2 => "VO2",
                :phn => "PHN"
            };
        } else {
            return {
                :stp => "STEP",
                :cal => "CALO",
                :dst => "DIST",
                :flr => "FLOR",
                :prs => "PRES",
                :bat => "BATT",
                :syn => "SYNC",
                :chg => "CHRG",
                :alt => "ALTD",
                :bdb => "BDBT",
                :vo2 => "VO2M",
                :phn => "PHON"
            };
        }
    }

    // label at STATS_LABEL_X, value at STATS_VALUE_X (no measuring)
    private function _drawLabelValueLeft(dc as Dc, y, label, value, font) {

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(STATS_LABEL_X, y, font, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(STATS_VALUE_X, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Right column, white value
    private function _drawLabelValueRight(dc as Dc, y, label, value, font, margin) {
        _drawLabelValueRightColored(dc, y, label, value, font, margin, Graphics.COLOR_WHITE);
    }

    // Right column, custom value colour – keeps VO2/SYNC/PHON perfectly aligned
    private function _drawLabelValueRightColored(dc as Dc, y, label, value, font, margin, valueColor) {
        var lw = dc.getTextWidthInPixels(label, font);
        var vw = dc.getTextWidthInPixels(value, font);
        var total = lw + vw;

        var startX = dc.getWidth() - margin - total;

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(startX, y, font, label, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(valueColor, Graphics.COLOR_BLACK);
        dc.drawText(startX + lw, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ---------- drawing ----------

    function onUpdate(dc as Dc) as Void {

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var marginTop = 6;
        var row = 0;
        var rowH = 28;
        var dOffset = 8;

        // Time / date
        var clock = System.getClockTime();
        var nowMoment = Time.now();
        var epoch = nowMoment.value();
        var gInfo = Gregorian.info(nowMoment, Time.FORMAT_SHORT);

        // UTC + offset
        var localSecs = clock.hour * 3600 + clock.min * 60 + clock.sec;
        var offsetSecs = clock.timeZoneOffset + clock.dst;
        var utcSecs = localSecs - offsetSecs;

        if (utcSecs < 0) {
            utcSecs += 86400;
        }
        if (utcSecs >= 86400) {
            utcSecs -= 86400;
        }

        var utcHour = utcSecs / 3600;
        var utcMin = (utcSecs % 3600) / 60;
        var utcSec = utcSecs % 60;

        var offsetMins = offsetSecs / 60;
        var offsetSign = "+";
        if (offsetMins < 0) {
            offsetSign = "-";
            offsetMins = -offsetMins;
        }
        var offH = offsetMins / 60;
        var offM = offsetMins % 60;
        var offsetStr = offsetSign + _fmt2(offH) + _fmt2(offM);
        var timeStr = _fmt2(clock.hour) + ":" +
                      _fmt2(clock.min) + ":" +
                      _fmt2(clock.sec);

        // ActivityMonitor data
        var actInfo = ActivityMonitor.getInfo();
        var steps = 0;
        var stepGoal = 0;
        var calories = 0;
        var distM = 0.0; // metres
        var floors = 0;
        var floorGoal = 0;

        if (actInfo != null) {
            if (actInfo.steps != null) {
                steps = actInfo.steps;
            }

            if (actInfo.stepGoal != null) {
                stepGoal = actInfo.stepGoal;
            }

            if (actInfo.calories != null) {
                calories = actInfo.calories;
            }

            if (actInfo.distance != null) {
                // docs: distance in centimetres; /100 -> metres
                distM = actInfo.distance / 100.0;
            }

            if (actInfo.floorsClimbed != null) {
                floors = actInfo.floorsClimbed;
            }

            if (actInfo.floorsClimbedGoal != null) {
                floorGoal = actInfo.floorsClimbedGoal;
            }
        }

        // Activity data (HR, pressure, altitude)
        var activityInfo = Activity.getActivityInfo();
        var curHr = null;
        var pressurePa = null;
        if (activityInfo != null) {

            if (activityInfo.currentHeartRate != null) {
                curHr = activityInfo.currentHeartRate;
            }

            if (activityInfo.ambientPressure != null) {
                pressurePa = activityInfo.ambientPressure;
            }

        }

        // Resting HR and VO2 from profile
        var restHr = null;
        var vo2Run = null;
        var vo2Bike = null;
        var profile = UserProfile.getProfile();

        if (profile != null) {

            if (profile.restingHeartRate != null) {
                restHr = profile.restingHeartRate;
            } else if (profile.averageRestingHeartRate != null) {
                restHr = profile.averageRestingHeartRate;
            }

            if (profile.vo2maxRunning != null) {
                vo2Run = profile.vo2maxRunning;
            }

            if (profile.vo2maxCycling != null) {
                vo2Bike = profile.vo2maxCycling;
            }
        }

        // Body Battery (SensorHistory, newest sample)
        var bodyBattery = null;
        try {
            var bbIter = SensorHistory.getBodyBatteryHistory({ :period => 1 });
            if (bbIter != null) {
                var bbSample = bbIter.next();
                if (bbSample != null && bbSample.data != null) {
                    bodyBattery = bbSample.data;
                }
            }
        } catch (ex) {
            bodyBattery = null;
        }

        // Battery
        var stats = System.getSystemStats();
        var battery = stats.battery;
        var charging = stats.charging;

        // Phone connection → last sync minutes + current state
        var devSettings = System.getDeviceSettings();
        var phoneConnected = false;
        if (devSettings != null && devSettings.phoneConnected) {
            _lastPhoneConnectMoment = nowMoment;
            phoneConnected = true;
        }

        var syncStr = "--min";
        if (_lastPhoneConnectMoment != null) {
            var diffSecs = nowMoment.value() - _lastPhoneConnectMoment.value();
            if (diffSecs < 0) {
                diffSecs = 0;
            }
            var diffMin = diffSecs / 60;
            if (diffMin > 999) {
                diffMin = 999;
            }
            syncStr = diffMin.toString() + "min";
        }

        var labels = _getLabels();

        var calGoal = 0;
        var distGoalM = 0.0; // metres

        try {
            var g = Properties.getValue("CalGoal");
            if (g != null) {
                calGoal = g.toNumber();
            }
        } catch (ex) {
            // pass
        }

        try {
            var d = Properties.getValue("DistGoalM");
            if (d != null) {
                distGoalM = d.toFloat();
            }
        } catch (ex) {
            // pass
        }

        // Position info (for altitude fallback)
        var posInfo = Position.getInfo();

        // ---------- Row 1: weekday (centered, capitalised) ----------

        var y = marginTop + row * rowH;
        var dateFont = Graphics.FONT_XTINY;
        var weekFont = Graphics.FONT_SYSTEM_XTINY;

        var dowStr = _dow3(gInfo.day_of_week);
        if (dowStr.length() >= 1) {
            dowStr = dowStr.substring(0,1).toUpper() + dowStr.substring(1,3);
        }

        var gapStr = " ";
        var weekStr = "W" + _fmt2(_isoWeekNumber(gInfo.year, gInfo.month, gInfo.day));
        var dowW = dc.getTextWidthInPixels(dowStr, dateFont);
        var gapW = dc.getTextWidthInPixels(gapStr, dateFont);
        var weekW = dc.getTextWidthInPixels(weekStr, weekFont);
        var topRowX = (w - (dowW + gapW + weekW)) / 2;

        dc.setColor(COLOR_MONTH, Graphics.COLOR_BLACK);
        dc.drawText(topRowX, y, dateFont, dowStr, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(topRowX + dowW, y, dateFont, gapStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(topRowX + dowW + gapW, y + 1, weekFont, weekStr, Graphics.TEXT_JUSTIFY_LEFT);
        row += 1;

        // ---------- Row 2: YYYY-MM-DD ----------

        y = marginTop + row * rowH;

        var yearStr  = gInfo.year.toString();
        var monthStr = _fmt2(gInfo.month);
        var dayStr   = _fmt2(gInfo.day);
        var dashStr  = "-";
        var doyStr   = " D" + _fmt3(_dayOfYear(gInfo.year, gInfo.month, gInfo.day));
        var doyGapPx = 4;

        var yearW  = dc.getTextWidthInPixels(yearStr, dateFont);
        var monthW = dc.getTextWidthInPixels(monthStr, dateFont);
        var dayW   = dc.getTextWidthInPixels(dayStr, dateFont);
        var dashW  = dc.getTextWidthInPixels(dashStr, dateFont);

        var timeLeftX = (w - dc.getTextWidthInPixels(timeStr, Graphics.FONT_LARGE)) / 2;
        var x = timeLeftX;

        dc.setColor(COLOR_YEAR, Graphics.COLOR_BLACK);
        dc.drawText(x, y, dateFont, yearStr, Graphics.TEXT_JUSTIFY_LEFT);
        x += yearW;

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(x, y, dateFont, dashStr, Graphics.TEXT_JUSTIFY_LEFT);
        x += dashW;

        dc.setColor(COLOR_MONTH, Graphics.COLOR_BLACK);
        dc.drawText(x, y, dateFont, monthStr, Graphics.TEXT_JUSTIFY_LEFT);
        x += monthW;

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(x, y, dateFont, dashStr, Graphics.TEXT_JUSTIFY_LEFT);
        x += dashW;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(x, y, dateFont, dayStr, Graphics.TEXT_JUSTIFY_LEFT);
        x += dayW;

        x += doyGapPx;
        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(x, y, dateFont, doyStr, Graphics.TEXT_JUSTIFY_LEFT);

        row += 1;

        // ---------- Row 3: time (white) ----------
 
        y = marginTop + row * rowH;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(w / 2, y, Graphics.FONT_LARGE, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        row += 2;

        // ---------- Row 4: epoch (red) + UTC (blue) ----------

        y = marginTop + row * rowH;

        var epochStr = epoch.toString();
        var utcStr = _fmt2(utcHour) + ":" + _fmt2(utcMin) + ":" + _fmt2(utcSec);
        var utcFull = " " + utcStr + " " + offsetStr;

        var fontTz = Graphics.FONT_XTINY;

        var epochW = dc.getTextWidthInPixels(epochStr, fontTz);
        var utcW   = dc.getTextWidthInPixels(utcFull, fontTz);
        var totalTz = epochW + utcW;

        var xTz = (w - totalTz) / 2;

        dc.setColor(COLOR_EPOCH, Graphics.COLOR_BLACK);
        dc.drawText(xTz - 16, y, fontTz, epochStr, Graphics.TEXT_JUSTIFY_LEFT);
        xTz += epochW + 16;

        dc.setColor(COLOR_UTC, Graphics.COLOR_BLACK);
        dc.drawText(xTz, y, fontTz, utcFull, Graphics.TEXT_JUSTIFY_LEFT);

        row += 1;

        // ---------- Row 5: divider ----------

        y = marginTop + row * rowH + (rowH * 0.25);
        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawLine(6, y, w - 6, y);

        var fontStats = Graphics.FONT_XTINY;

        // ---------- Row 6: HR / resting HR ----------

        y = marginTop + dOffset + row * rowH;
        var hrLeft;
        if (curHr == null) {
            hrLeft = "--bpm";
        } else {
            hrLeft = curHr.toString() + "bpm";
        }

        var hrRight = null;
        if (restHr != null) {
            hrRight = restHr.toString() + "r.bpm";
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(STATS_LABEL_X, y, fontStats, hrLeft, Graphics.TEXT_JUSTIFY_LEFT);

        if (hrRight != null) {
            var twHr = dc.getTextWidthInPixels(hrRight, fontStats);
            dc.drawText(w - 8 - twHr, y, fontStats, hrRight,
                        Graphics.TEXT_JUSTIFY_LEFT);
        }

        row += 1;

        // ---------- Row 7: Steps / goal (data turns green at goal) ----------

        y = marginTop + dOffset + row * rowH;
        var stpLabel = labels[:stp];

        var stepsStr = steps.toString();
        var goalStr  = "/" + stepGoal.toString();

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(STATS_LABEL_X, y, fontStats, stpLabel, Graphics.TEXT_JUSTIFY_LEFT);

        var xSteps = STATS_VALUE_X;

        // data colour: white until goal reached, then green
        var stepColor = Graphics.COLOR_WHITE;
        if (stepGoal > 0 && steps >= stepGoal) {
            stepColor = COLOR_STEPS;
        }

        dc.setColor(stepColor, Graphics.COLOR_BLACK);
        dc.drawText(xSteps, y, fontStats, stepsStr, Graphics.TEXT_JUSTIFY_LEFT);
        xSteps += dc.getTextWidthInPixels(stepsStr, fontStats);

        // goal always white
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(xSteps, y, fontStats, goalStr, Graphics.TEXT_JUSTIFY_LEFT);

        row += 1;

        // ---------- Row 8: Calories / goal (data turns green at goal) ----------

        y = marginTop + dOffset + row * rowH;
        var calLabel = labels[:cal];

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(STATS_LABEL_X, y, fontStats, calLabel, Graphics.TEXT_JUSTIFY_LEFT);

        var xCal = STATS_VALUE_X;

        var calColor = Graphics.COLOR_WHITE;
        if (calGoal > 0 && calories >= calGoal) {
            calColor = COLOR_STEPS;
        }

        var calNowStr = calories.toString();
        dc.setColor(calColor, Graphics.COLOR_BLACK);
        dc.drawText(xCal, y, fontStats, calNowStr, Graphics.TEXT_JUSTIFY_LEFT);
        xCal += dc.getTextWidthInPixels(calNowStr, fontStats);

        if (calGoal > 0) {
            var calGoalStr = "/" + calGoal.toString();
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(xCal, y, fontStats, calGoalStr, Graphics.TEXT_JUSTIFY_LEFT);
        }

        row += 1;

        // ---------- Row 9: Body Battery (left) + SYNC (right) ----------

        y = marginTop + dOffset + row * rowH;

        var bdbLabel = labels[:bdb];
        var bdbVal = "--";
        if (bodyBattery != null) {
            var bbInt = bodyBattery.toNumber();
            if (bbInt < 0) { bbInt = 0; }
            if (bbInt > 100) { bbInt = 100; }
            bdbVal = bbInt.toString();
        }
        _drawLabelValueLeft(dc, y, bdbLabel, bdbVal, fontStats);

        // SYNC right side stays as you already have it
        var synLabel = labels[:syn];
        var synVal = " " + syncStr;
        _drawRightCol(dc, y, synLabel, synVal, fontStats, Graphics.COLOR_WHITE);

        row += 1;

        // ---------- Row 10: Floors + VO2 (right, unchanged) ----------

        y = marginTop + dOffset + row * rowH;

        var flrLabel = labels[:flr];

        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(STATS_LABEL_X, y, fontStats, flrLabel, Graphics.TEXT_JUSTIFY_LEFT);

        var xFlr = STATS_VALUE_X;

        var flrColor = Graphics.COLOR_WHITE;
        if (floorGoal > 0 && floors >= floorGoal) {
            flrColor = COLOR_STEPS;
        }

        var flrNowStr = floors.toString();
        dc.setColor(flrColor, Graphics.COLOR_BLACK);
        dc.drawText(xFlr, y, fontStats, flrNowStr, Graphics.TEXT_JUSTIFY_LEFT);
        xFlr += dc.getTextWidthInPixels(flrNowStr, fontStats);

        var flrGoalStr = "/" + floorGoal.toString();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(xFlr, y, fontStats, flrGoalStr, Graphics.TEXT_JUSTIFY_LEFT);

        var vo2Label = labels[:vo2];
        var vo2Val = "--";
        if (vo2Run != null) {
            vo2Val = vo2Run.toNumber().toString();
        } else if (vo2Bike != null) {
            vo2Val = vo2Bike.toNumber().toString();
        }
        _drawRightCol(dc, y, vo2Label, vo2Val, fontStats, Graphics.COLOR_WHITE);

        row += 1;

        // ---------- Row 11: Altitude + PHON (right) ----------

        y = marginTop + dOffset + row * rowH;
        var altLbl = labels[:alt];
        var altStr = "--";

        var altVal = null;

        if (activityInfo != null && activityInfo.altitude != null) {
            altVal = activityInfo.altitude.toNumber();
        } else if (posInfo != null && posInfo.altitude != null) {
            altVal = posInfo.altitude.toNumber();
        }

        if (altVal != null) {
            if (altVal < -200) {
                altVal = null;
            }
        }

        if (altVal != null) {
            var altInt = (altVal + 0.5).toNumber();
            altStr = altInt.toString() + "m";
        }

        _drawLabelValueLeft(dc, y, altLbl, altStr, fontStats);

        // PHON right side, aligned with VO2/SYNC
        var phnLabel = labels[:phn];
        var phnVal = phoneConnected ? "T" : "F";
        var valueColor = phoneConnected ? COLOR_BATT_FULL : COLOR_BATT_LOW;

        _drawRightCol(dc, y, phnLabel, phnVal, fontStats, valueColor);

        row += 1;

        // ---------- Row 12: Pressure ----------

        y = marginTop + dOffset + row * rowH;
        var prsLabel = labels[:prs];
        var prsVal;

        if (pressurePa == null) {
            prsVal = "-- kPa";
        } else {
            var scaled = Math.round(pressurePa.toNumber() / 100.0).toLong();

            var whole = scaled / 10;
            var frac  = scaled % 10;

            prsVal = whole.toString() + "." + frac.toString() + " kPa";
        }


        _drawLabelValueLeft(dc, y, prsLabel, prsVal, fontStats);
        row += 1;

        // ---------- Row 13: Distance (km, goal-aware colour) ----------

        y = marginTop + dOffset + row * rowH;

        var dstLabel = labels[:dst];
        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(STATS_LABEL_X, y, fontStats, dstLabel, Graphics.TEXT_JUSTIFY_LEFT);

        // metres -> nearest 10m, then km
        var metersNow = distM.toNumber();
        if (metersNow < 0) {
            metersNow = 0;
        }
        var metersRounded = Math.round(metersNow / 10.0) * 10.0; // still float, but fine
        var kmNow = metersRounded / 1000.0;
        var dNowStr = _fmtKm(kmNow);

        var xDst = STATS_VALUE_X;

        // colour: green once goal reached
        var dstColor = Graphics.COLOR_WHITE;
        if (distGoalM > 0 && metersNow >= distGoalM) {
            dstColor = COLOR_STEPS;
        }

        dc.setColor(dstColor, Graphics.COLOR_BLACK);
        dc.drawText(xDst, y, fontStats, dNowStr, Graphics.TEXT_JUSTIFY_LEFT);
        xDst += dc.getTextWidthInPixels(dNowStr, fontStats);

        if (distGoalM > 0) {
            var goalMeters = distGoalM.toNumber();
            if (goalMeters < 0) {
                goalMeters = 0;
            }
            var goalRounded = Math.round(goalMeters / 10.0) * 10.0;
            var goalKm = goalRounded / 1000.0;
            var goalDistStr = "/" + _fmtKm(goalKm) + "km";

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(xDst, y, fontStats, goalDistStr, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(xDst, y, fontStats, "km", Graphics.TEXT_JUSTIFY_LEFT);
        }
        
        row += 1;

        // ---------- Bottom: Battery (rounded, 3-digit, centred) ----------

        var h = dc.getHeight();
        y = h - (2 * rowH) - 4;

        var batLabel = labels[:bat];

        // Round to nearest int, then clamp
        var bInt = (battery + 0.5).toNumber();
        if (bInt < 0) { bInt = 0; }
        if (bInt > 100) { bInt = 100; }

        var batPctStr = _fmt3(bInt) + "%";

        // Measure label and value so we can centre the pair
        var labelW = dc.getTextWidthInPixels(batLabel, fontStats);
        var valueW = dc.getTextWidthInPixels(batPctStr, fontStats);
        var totalW = labelW + BAT_LABEL_GAP + valueW;

        var xBat = (w - totalW) / 2;

        // Draw label (grey)
        dc.setColor(COLOR_LABEL, Graphics.COLOR_BLACK);
        dc.drawText(xBat, y, fontStats, batLabel, Graphics.TEXT_JUSTIFY_LEFT);
        xBat += labelW + BAT_LABEL_GAP;

        dc.setColor(COLOR_BATT, Graphics.COLOR_BLACK);
        if (bInt < 40) {
            dc.setColor(COLOR_BATT_LOW, Graphics.COLOR_BLACK);
        }
        if (bInt > 60) {
            dc.setColor(COLOR_BATT, Graphics.COLOR_BLACK);
        }
        if (bInt > 80) {
            dc.setColor(COLOR_BATT_FULL, Graphics.COLOR_BLACK);
        }
        dc.drawText(xBat, y, fontStats, batPctStr, Graphics.TEXT_JUSTIFY_LEFT);

        if (charging) {
            y = h - (1 * rowH) - 4;
            batPctStr = labels[:chg];
            var chargeW = dc.getTextWidthInPixels(batPctStr, fontStats);
            xBat = (w - chargeW) / 2;
            dc.setColor(COLOR_BATT_LOW, Graphics.COLOR_BLACK);
            dc.drawText(xBat, y, fontStats, batPctStr, Graphics.TEXT_JUSTIFY_LEFT);
        }

    }

    function onShow() as Void { }
    function onHide() as Void { }
    function onExitSleep() as Void { }
    function onEnterSleep() as Void { }
}
