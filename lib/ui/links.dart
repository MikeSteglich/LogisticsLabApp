/// Links in the browser (a new tab) - a page next to the web app (relative) or an address on the internet.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

/// the source code of the free software (AGPL)
const sourceRepositories = [
  'github.com/MikeSteglich/LogisticsLabApp',
  'github.com/MikeSteglich/pyLogisticsLab',
  'github.com/MikeSteglich/pyCmpl',
  'github.com/MikeSteglich/Cmpl2',
];

/// a text as a link - in the browser a real link of the page: window.open after a tap is blocked as a popup
class TextLink extends StatelessWidget {
  final String text;
  final String url;
  final TextStyle? style;
  const TextLink(this.text, this.url, {super.key, this.style});

  @override
  Widget build(BuildContext context) => Link(
    uri: Uri.base.resolve(url),
    target: LinkTarget.blank,
    builder: (context, follow) => InkWell(
      onTap: follow,
      child: Text(text, style: style),
    ),
  );
}
