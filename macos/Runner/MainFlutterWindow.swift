import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // large enough for map and data area side by side (from 900 points width), at most the visible screen
    let visible = (self.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = NSSize(width: min(1440, visible.width), height: min(900, visible.height))
    self.setFrame(
      NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height),
      display: true)
    self.minSize = NSSize(width: 640, height: 480)
    // one window - no tab bar of macOS (and no menu items for it)
    NSWindow.allowsAutomaticWindowTabbing = false
    self.tabbingMode = .disallowed
    self.title = "LogisticsLab Studio"

    // title of the window from the app: the open file
    FlutterMethodChannel(name: "logisticslab/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { [weak self] call, result in
        if call.method == "title", let title = call.arguments as? String {
          self?.title = title
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // the close button quits the app like Cmd+Q - the app asks about unsaved changes first
    self.delegate = self

    super.awakeFromNib()
  }

  /// the window closes with the app: the request goes to the app (AppLifecycleListener.onExitRequested), which
  /// may keep it open
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(sender)
    return false
  }
}
