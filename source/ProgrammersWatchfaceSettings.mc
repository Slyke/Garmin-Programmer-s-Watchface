import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.WatchUi;

var DEFAULT_CAL_GOAL = 500;

class ProgrammersWatchfaceSettingsMenu extends WatchUi.Menu2 {

    private var _calGoalItem;

    function initialize() {
        Menu2.initialize({ :title => "Settings" });

        _calGoalItem = new WatchUi.MenuItem(
            "Daily calorie goal",
            _formatCalGoal(),
            "CalGoal",
            null
        );

        addItem(_calGoalItem);
    }

    function onShow() as Void {
        _refresh();
    }

    function _refresh() as Void {
        if (_calGoalItem != null) {
            _calGoalItem.setSubLabel(_formatCalGoal());
        }
    }

    private function _formatCalGoal() as String {
        var goal = DEFAULT_CAL_GOAL;

        try {
            var value = Properties.getValue("CalGoal");
            if (value != null) {
                goal = value.toNumber();
            }
        } catch (ex) {
            goal = DEFAULT_CAL_GOAL;
        }

        return goal.toString() + " cal";
    }
}

class ProgrammersWatchfaceSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize(menu as ProgrammersWatchfaceSettingsMenu) {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == "CalGoal" && WatchUi has :TextPicker) {
            var goal = DEFAULT_CAL_GOAL;

            try {
                var value = Properties.getValue("CalGoal");
                if (value != null) {
                    goal = value.toNumber();
                }
            } catch (ex) {
                goal = DEFAULT_CAL_GOAL;
            }

            WatchUi.pushView(
                new WatchUi.TextPicker(goal.toString()),
                new ProgrammersWatchfaceCalGoalTextPickerDelegate(),
                WatchUi.SLIDE_IMMEDIATE
            );
        }
    }
}

class ProgrammersWatchfaceCalGoalTextPickerDelegate extends WatchUi.TextPickerDelegate {

    function initialize() {
        TextPickerDelegate.initialize();
    }

    function onCancel() as Lang.Boolean {
        return true;
    }

    function onTextEntered(text as String, changed as Lang.Boolean) as Lang.Boolean {
        var goal = _parseCalGoal(text);
        if (goal == null) {
            return false;
        }

        try {
            Properties.setValue("CalGoal", goal);
            WatchUi.requestUpdate();
        } catch (ex) {
            return false;
        }

        return true;
    }

    private function _parseCalGoal(text as String) {
        if (text == null || text.length() == 0) {
            return null;
        }

        var goal = null;
        try {
            goal = text.toNumber();
        } catch (ex) {
            return null;
        }

        if (goal < 0) {
            goal = 0;
        }
        if (goal > 20000) {
            goal = 20000;
        }

        return goal;
    }
}
