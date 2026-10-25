/// Log of the app for runs where the timing matters (e.g. the import) - a file on the desktop systems, nothing in
/// the browser. macOS: ~/Library/Logs/LogisticsLab/app.log beside the log of the core.
library;

export 'app_log_stub.dart' if (dart.library.io) 'app_log_io.dart';
