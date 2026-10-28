/// the browser: no other window of the app (new_window.dart)
library;

bool get newWindowSupported => false;

Future<void> openNewWindow() async {}

/// the browser: no home folder
String? get homeFolder => null;
