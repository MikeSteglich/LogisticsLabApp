/// Local computing: the core of LogisticsLab as child process - JSON-RPC 2.0 over stdin/stdout (logisticsLabCore.stdio).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

import 'backend.dart';

const supported = true;

Backend createLocalBackend(BackendSettings s) =>
    LocalBackend(s.executable, s.arguments, workingDirectory: s.workingDirectory.isEmpty ? null : s.workingDirectory);

class LocalBackend implements Backend {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  Process? _process;
  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _ready = Completer<void>();
  final _done = <String, Completer<void>>{}; // problem id -> finished
  final _finished = <String>{}; // finished before solveScenario() waits for them
  final _onStatus = <String, StatusCallback>{};
  final _stderr = StringBuffer();

  LocalBackend(this.executable, this.arguments, {this.workingDirectory});

  @override
  Future<void> start() async {
    if (executable.isEmpty) throw BackendException(500, 'no program for local computing - see settings');
    try {
      _process = await Process.start(executable, arguments, workingDirectory: workingDirectory);
    } on ProcessException catch (e) {
      throw BackendException(500, '$executable: ${e.message}');
    }
    // stderr: log output of the core, CMPL and HiGHS - stdout belongs to the protocol only
    _process!.stderr.transform(utf8.decoder).listen((t) {
      _stderr.write(t);
      if (_stderr.length > 20000) {
        final s = _stderr.toString();
        _stderr
          ..clear()
          ..write(s.substring(s.length - 10000));
      }
    });
    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onDone: () {
            final e = BackendException(500, 'local solver has stopped\n${_lastLines()}');
            if (!_ready.isCompleted) _ready.completeError(e);
            _failAll(e);
          },
        );
    await _ready.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw BackendException(500, 'local solver does not start\n${_lastLines()}'),
    );
  }

  String _lastLines() => _stderr.toString().trim().split('\n').reversed.take(5).toList().reversed.join('\n');

  void _onLine(String line) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    if (msg['id'] != null) {
      final completer = _pending.remove(msg['id']);
      if (msg.containsKey('error')) {
        final e = msg['error'];
        final data = e['data'];
        final status = data is Map && data['httpStatus'] is int ? data['httpStatus'] as int : 500;
        completer?.completeError(BackendException(status, '${e['message']}'));
      } else {
        completer?.complete(msg['result']);
      }
    } else if (msg['method'] == 'ready') {
      if (!_ready.isCompleted) _ready.complete();
    } else if (msg['method'] == 'jobStatus') {
      final status = ProblemAnswer.fromJson(msg['params'] as Map<String, dynamic>);
      _onStatus[status.id]?.call(status);
      if (finishedStatus.contains(status.status)) {
        _finished.add(status.id);
        _done[status.id]?.complete();
      }
    }
  }

  void _failAll(Object error) {
    for (final c in _pending.values) {
      c.completeError(error);
    }
    _pending.clear();
    for (final c in _done.values) {
      if (!c.isCompleted) c.completeError(error);
    }
  }

  Future<dynamic> _call(String method, Map<String, dynamic> params) {
    final p = _process;
    if (p == null) return Future.error(BackendException(500, 'local solver is not running'));
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    p.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return completer.future;
  }

  @override
  Future<ProblemAnswer> solveScenario(Map<String, dynamic> scenario, String problem, {StatusCallback? onStatus}) async {
    final job = ProblemAnswer.fromJson(
      await _call('solveScenario', {'scenario': scenario, 'problem': problem}) as Map<String, dynamic>,
    );
    if (onStatus != null) {
      _onStatus[job.id] = onStatus;
      onStatus(job);
    }
    try {
      // the notification can arrive before the answer of solveScenario
      if (!_finished.contains(job.id)) await (_done[job.id] = Completer<void>()).future;
    } finally {
      _done.remove(job.id);
      _finished.remove(job.id);
      _onStatus.remove(job.id);
    }
    return ProblemAnswer.fromJson(await _call('result', {'id': job.id}) as Map<String, dynamic>);
  }

  @override
  Future<void> cancel(String id) async => await _call('cancel', {'id': id});

  @override
  Future<List<LatLng>> route(List<LatLng> points, String travelmode) async {
    final r =
        await _call('routing', {
              'coordinates': [
                for (final p in points) [p.latitude, p.longitude],
              ],
              'travelmode': travelmode,
            })
            as Map<String, dynamic>;
    return [for (final c in r['route'] as List) LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble())];
  }

  @override
  Future<void> close() async {
    final p = _process;
    if (p == null) return;
    try {
      await _call('shutdown', {}).timeout(const Duration(seconds: 5));
    } catch (_) {}
    await p.stdin.close();
    await p.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        p.kill();
        return -1;
      },
    );
    _process = null;
  }
}

/// Defaults for local computing: LOGLAB_STDIO (program), LOGLAB_STDIO_ARGS (arguments separated by spaces),
/// LOGLAB_STDIO_DIR (working directory) - e.g. python, "-m logisticsLabCore.stdio" and the pyLogisticsLab directory.
BackendSettings defaultBackendSettings() {
  final env = Platform.environment;
  final args = env['LOGLAB_STDIO_ARGS'];
  return BackendSettings(
    executable: env['LOGLAB_STDIO'] ?? '',
    arguments: args == null || args.trim().isEmpty ? const [] : args.trim().split(RegExp(r'\s+')),
    workingDirectory: env['LOGLAB_STDIO_DIR'] ?? '',
  );
}
