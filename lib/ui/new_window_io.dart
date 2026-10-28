/// the desktop: another instance of the app (new_window.dart)
library;

import 'dart:io';

bool get newWindowSupported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// macOS: the bundle once more (open -n) - Windows and Linux: the program detached from this one
Future<void> openNewWindow() async {
  final exe = Platform.resolvedExecutable;
  if (Platform.isMacOS) {
    // .../LogisticsLab Studio.app/Contents/MacOS/LogisticsLabStudio -> the .app
    final app = File(exe).parent.parent.parent.path;
    await Process.start('open', ['-n', app], mode: ProcessStartMode.detached);
  } else {
    await Process.start(exe, const [], mode: ProcessStartMode.detached, workingDirectory: File(exe).parent.path);
  }
}
