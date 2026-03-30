import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ProgrammersWatchfaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new ProgrammersWatchfaceView() ];
    }

    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var menu = new ProgrammersWatchfaceSettingsMenu();
        return [ menu, new ProgrammersWatchfaceSettingsMenuDelegate(menu) ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

}

function getApp() as ProgrammersWatchfaceApp {
    return Application.getApp() as ProgrammersWatchfaceApp;
}
