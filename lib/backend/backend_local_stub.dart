import 'backend.dart';

const supported = false;

Backend createLocalBackend(BackendSettings s) => throw UnsupportedError('no local computing in the browser');

BackendSettings defaultBackendSettings() => const BackendSettings(remote: true);
