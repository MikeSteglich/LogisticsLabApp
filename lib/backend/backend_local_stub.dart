import 'backend.dart';

const supported = false;

Backend createLocalBackend(BackendSettings s) => throw UnsupportedError('no local computing in the browser');

/// the server of the browser app: LOGLAB_SERVER given at the build (flutter build web --dart-define=LOGLAB_SERVER=...),
/// else /v1/ of the host the app comes from - nginx serves both (deploy/setupServer.sh)
const _server = String.fromEnvironment('LOGLAB_SERVER');

BackendSettings defaultBackendSettings() =>
    BackendSettings(remote: true, url: _server.isNotEmpty ? _server : Uri.base.resolve('/v1/').toString());
