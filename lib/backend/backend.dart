/// Computing of the app - local (child process with JSON-RPC over stdio) or remote (REST server).
///
/// Both solve a problem of a scenario (method solveScenario, endpoint /v1/scenario) and return the answer with the
/// solution document (llsol) in the field solution.
library;

import 'package:latlong2/latlong.dart';

import 'backend_local_stub.dart' if (dart.library.io) 'backend_local_io.dart' as local;
import 'backend_remote.dart';

class BackendException implements Exception {
  final int httpStatus;
  final String message;
  BackendException(this.httpStatus, this.message);

  @override
  String toString() => message;
}

/// Answer of solve, status, result and cancel - results and solution only if the problem is finished.
class ProblemAnswer {
  final String id;
  final String status; // waiting, running, solution, noSolution, error, cancelled
  final String message;
  final Map<String, dynamic>? solution;

  ProblemAnswer(this.id, this.status, this.message, this.solution);

  factory ProblemAnswer.fromJson(Map<String, dynamic> json) => ProblemAnswer(
    json['id'] as String? ?? '',
    json['status'] as String? ?? 'error',
    json['message'] as String? ?? '',
    json['solution'] as Map<String, dynamic>?,
  );
}

const finishedStatus = ['solution', 'noSolution', 'error', 'cancelled'];

typedef StatusCallback = void Function(ProblemAnswer status);

abstract class Backend {
  Future<void> start();

  Future<ProblemAnswer> solveScenario(Map<String, dynamic> scenario, String problem, {StatusCallback? onStatus});

  Future<void> cancel(String id);

  /// course of the roads between the points (OSM)
  Future<List<LatLng>> route(List<LatLng> points, String travelmode);

  Future<void> close();
}

class BackendSettings {
  final bool remote;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final String url;
  final String apiKey;

  const BackendSettings({
    this.remote = false,
    this.executable = '',
    this.arguments = const [],
    this.workingDirectory = '',
    this.url = 'http://127.0.0.1:8000/v1/',
    this.apiKey = '',
  });

  BackendSettings copyWith({
    bool? remote,
    String? executable,
    List<String>? arguments,
    String? workingDirectory,
    String? url,
    String? apiKey,
  }) => BackendSettings(
    remote: remote ?? this.remote,
    executable: executable ?? this.executable,
    arguments: arguments ?? this.arguments,
    workingDirectory: workingDirectory ?? this.workingDirectory,
    url: url ?? this.url,
    apiKey: apiKey ?? this.apiKey,
  );
}

/// in the browser only the REST server is possible
bool get localBackendSupported => local.supported;

Backend createBackend(BackendSettings s) => s.remote || !local.supported
    ? RemoteBackend(Uri.parse(s.url.endsWith('/') ? s.url : '${s.url}/'), s.apiKey)
    : local.createLocalBackend(s);

BackendSettings defaultBackendSettings() => local.defaultBackendSettings();
