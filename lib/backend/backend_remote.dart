/// Remote computing: a LogisticsLab server (REST, api key) - also in the browser.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'backend.dart';

class RemoteBackend implements Backend {
  final Uri baseUrl; // e.g. http://127.0.0.1:8000/v1/
  final String apiKey;
  final Duration pollInterval;
  final _client = http.Client();
  final _cancelled = <String>{};

  RemoteBackend(this.baseUrl, this.apiKey, {this.pollInterval = const Duration(milliseconds: 400)});

  @override
  Future<void> start() async {}

  Future<(int, Map<String, dynamic>)> _post(String endpoint, Map<String, dynamic> body) async {
    final http.Response r;
    try {
      r = await _client.post(
        baseUrl.resolve(endpoint),
        headers: {'Content-Type': 'application/json', if (apiKey.isNotEmpty) 'X-API-Key': apiKey},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw BackendException(503, 'server $baseUrl not available: $e');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      throw BackendException(r.statusCode, 'server $baseUrl: no JSON answer (${r.statusCode})');
    }
    return (r.statusCode, json is Map<String, dynamic> ? json : <String, dynamic>{'detail': json});
  }

  static String _message(Map<String, dynamic> b) => '${b['message'] ?? b['detail'] ?? b}';

  @override
  Future<ProblemAnswer> solveScenario(Map<String, dynamic> scenario, String problem, {StatusCallback? onStatus}) async {
    final (code, body) = await _post('scenario', {'scenario': scenario, 'problem': problem});
    if (code != 200) throw BackendException(code, _message(body));
    final id = body['id'] as String;
    String? lastStatus;
    while (true) {
      // /results answers 200 for solution, 404 for noSolution, 400 or 500 for error - the body is always the answer
      final (_, answerJson) = await _post('results', {'id': id});
      final answer = ProblemAnswer.fromJson(answerJson);
      if (answer.status != lastStatus) {
        lastStatus = answer.status;
        onStatus?.call(answer);
      }
      if (finishedStatus.contains(answer.status)) {
        _cancelled.remove(id);
        return answer;
      }
      await Future.delayed(pollInterval);
    }
  }

  @override
  Future<void> cancel(String id) async {
    _cancelled.add(id);
    await _post('cancel', {'id': id});
  }

  @override
  Future<List<LatLng>> route(List<LatLng> points, String travelmode) async {
    final (code, body) = await _post('routing', {
      'coordinates': [
        for (final p in points) [p.latitude, p.longitude],
      ],
      'travelmode': travelmode,
    });
    if (code != 200) throw BackendException(code, _message(body));
    return [for (final c in body['route'] as List) LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble())];
  }

  @override
  Future<void> close() async => _client.close();
}
