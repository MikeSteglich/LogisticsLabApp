/// Another window of the app: a second, independent instance - with its own scenario and its own computing core,
/// e.g. to compare two variants side by side. Not in the browser (a new tab of the browser does it).
library;

export 'new_window_stub.dart' if (dart.library.io) 'new_window_io.dart';
