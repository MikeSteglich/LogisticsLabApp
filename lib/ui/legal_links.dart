/// Impressum and Datenschutz of the browser app (web/impressum.html, web/datenschutz.html) - opened in a new tab;
/// the desktop apps have none (they are no service on the internet).
library;

export 'legal_links_stub.dart' if (dart.library.js_interop) 'legal_links_web.dart';
