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

  /// the solver or server is older than the app and does not know the request (e.g. convert)
  final bool outdated;

  BackendException(this.httpStatus, this.message, {this.outdated = false});

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

/// Hit of the geocoding: position and the address found.
class GeoHit {
  final LatLng position;
  final Map<String, dynamic> json; // name, street, postcode, city, country ...

  GeoHit(this.position, this.json);

  factory GeoHit.fromJson(Map<String, dynamic> j) {
    final c = j['coordinates'] as List;
    return GeoHit(LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()), j);
  }

  String _s(String k) => (json[k] as String?)?.trim() ?? '';

  /// address of a place without its name and country, e.g. "Hochschulring 1, 15745 Wildau"
  String get address => [_s('street'), '${_s('postcode')} ${_s('city')}'.trim()].where((p) => p.isNotEmpty).join(', ');

  /// details of the address as in the scenario (addressDetails)
  Map<String, dynamic> get addressDetails => {
    for (final (k, v) in [
      ('street', _s('street')),
      ('postcode', _s('postcode')),
      ('city', _s('city')),
      ('country', _s('countrycode').toUpperCase()),
    ])
      if (v.isNotEmpty) k: v,
  };

  /// the first hit of a reverse geocoding - null without one
  static GeoHit? fromReverse(Map<String, dynamic> answer) {
    final results = answer['results'] as List?;
    if (results == null || results.isEmpty || results.first is! Map) return null;
    return GeoHit.fromJson((results.first as Map).cast<String, dynamic>());
  }

  /// e.g. "TH Wildau, Hochschulring 1, 15745 Wildau, Germany"
  String get label => [
    _s('name'),
    _s('street'),
    '${_s('postcode')} ${_s('city')}'.trim(),
    _s('country'),
  ].where((p) => p.isNotEmpty).toSet().join(', ');

  /// request of the geo service coordinates (local and REST)
  static Map<String, dynamic> request(String address, LatLng? near, int limit) => {
    'adresses': [address],
    'limit': limit,
    if (near != null) 'near': [near.latitude, near.longitude],
  };

  /// hits of the first address of the answer
  static List<GeoHit> fromAnswer(Map<String, dynamic> answer) {
    final hits = answer['hits'] as List?;
    if (hits == null || hits.isEmpty || hits.first == null) return const [];
    return [for (final h in hits.first as List) GeoHit.fromJson(h as Map<String, dynamic>)];
  }
}

/// longest wait for a short request (convert, geocoding) - a solver that hangs does not block the app
const requestTimeout = Duration(seconds: 60);

const finishedStatus = ['solution', 'noSolution', 'error', 'cancelled'];

typedef StatusCallback = void Function(ProblemAnswer status);

abstract class Backend {
  Future<void> start();

  Future<ProblemAnswer> solveScenario(Map<String, dynamic> scenario, String problem, {StatusCallback? onStatus});

  Future<void> cancel(String id);

  /// course of the roads between the points (OSM)
  Future<List<LatLng>> route(List<LatLng> points, String travelmode);

  /// places of an address (OSM geocoding) - hits near [near] first
  Future<List<GeoHit>> geocode(String address, {LatLng? near, int limit = 5});

  /// address of a place (OSM reverse geocoding) - null if there is none
  Future<GeoHit?> reverse(LatLng position);

  /// scenario (llab) of an old LogisticsLab file (TPPX, TSPX, CLPX, DLPX, NWFX, VRPX) - the extension of
  /// [fileName] is the format; returns the scenario and its file name (e.g. drogma.clpx.llab)
  Future<(Map<String, dynamic>, String)> convert(String fileName, String content);

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
