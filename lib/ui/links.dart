/// Links in the browser (a new tab) - a page next to the web app (relative) or an address on the internet.
library;

import 'package:url_launcher/url_launcher.dart';

/// the source code of the free software (AGPL)
const sourceRepositories = [
  'github.com/MikeSteglich/LogisticsLabApp',
  'github.com/MikeSteglich/pyLogisticsLab',
  'github.com/MikeSteglich/pyCmpl',
  'github.com/MikeSteglich/Cmpl2',
];

Future<void> openLink(String url) => launchUrl(Uri.base.resolve(url), webOnlyWindowName: '_blank');
