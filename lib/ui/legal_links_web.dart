/// the browser: a page next to the app in a new tab (legal_links.dart)
library;

import 'package:web/web.dart' as web;

void openLegalPage(String page) => web.window.open(page, '_blank');
