import 'dart:io';

File? _file;

/// a line with the time - errors are ignored, the log must never disturb the app
void appLog(String message) {
  try {
    _file ??= () {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      final dir = Platform.isMacOS
          ? Directory('$home/Library/Logs/LogisticsLab')
          : Directory('${Directory.systemTemp.path}/LogisticsLab');
      dir.createSync(recursive: true);
      final f = File('${dir.path}/app.log');
      if (f.existsSync() && f.lengthSync() > 1000000) f.deleteSync(); // no endless growth
      return f;
    }();
    _file!.writeAsStringSync('${DateTime.now().toIso8601String()} $message\n', mode: FileMode.append);
  } catch (_) {}
}
