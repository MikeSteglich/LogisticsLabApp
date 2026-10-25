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

  /// help topics of the app (id, title, text to search) in its language - sent by the app (lib/main.dart)
  private var helpTopics: [(id: String, title: String, text: String)] = []

  private var menuChannel: FlutterMethodChannel? {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return nil }
    return FlutterMethodChannel(name: "logisticslab/menu", binaryMessenger: controller.engine.binaryMessenger)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // the search field of the help menu finds the help topics of the app
    NSApp.registerUserInterfaceItemSearchHandler(self)
    menuChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "helpTopics", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.helpTopics = ((args["topics"] as? [[String: String]]) ?? []).map {
        (id: $0["id"] ?? "", title: $0["title"] ?? "", text: $0["text"] ?? "")
      }
      // the help menu in the language of the app
      if let menu = args["menu"] as? String, let help = NSApp.helpMenu {
        help.title = menu
        help.supermenu?.items.first { $0.submenu == help }?.title = menu
        if let item = args["item"] as? String { help.items.first?.title = item }
      }
      result(nil)
    }
  }

  /// menu item "About LogisticsLab Studio" - shows the about dialog of the app (credits, thanks) instead of the panel of macOS
  @IBAction func showAbout(_ sender: Any?) {
    menuChannel?.invokeMethod("about", arguments: nil)
  }

  /// menu item of the help menu (cmd ?) - the help window of the app
  @IBAction func showHelp(_ sender: Any?) {
    menuChannel?.invokeMethod("help", arguments: [String: String]())
  }
}

/// the search field of the help menu: the help topics of the app (besides the menu items macOS finds itself)
extension AppDelegate: NSUserInterfaceItemSearching {
  private static func fold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  func searchForItems(withSearch searchString: String, resultLimit: Int,
                      matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void) {
    let words = AppDelegate.fold(searchString).split(separator: " ").map(String.init)
    let hits = helpTopics.filter { topic in
      let text = AppDelegate.fold(topic.text)
      return !words.isEmpty && words.allSatisfy { text.contains($0) }
    }
    handleMatchedItems(hits.prefix(resultLimit).map { $0.id })
  }

  func localizedTitles(forItem item: Any) -> [String] {
    guard let id = item as? String, let topic = helpTopics.first(where: { $0.id == id }) else { return [] }
    return [topic.title]
  }

  func performAction(forItem item: Any) {
    guard let id = item as? String else { return }
    menuChannel?.invokeMethod("help", arguments: ["topic": id])
  }

  func showAllHelpTopics(forSearch searchString: String) {
    menuChannel?.invokeMethod("help", arguments: ["query": searchString])
  }
}
