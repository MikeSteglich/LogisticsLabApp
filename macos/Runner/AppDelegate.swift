import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// menu item "About LogisticsLab Studio" - shows the about dialog of the app (credits, thanks) instead of the panel of macOS
  @IBAction func showAbout(_ sender: Any?) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    FlutterMethodChannel(name: "logisticslab/menu", binaryMessenger: controller.engine.binaryMessenger)
      .invokeMethod("about", arguments: nil)
  }
}
