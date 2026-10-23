/// Texts of the app in the chosen language.
///
/// One flat JSON file per language (assets/i18n/de.json, en.json). Placeholders {name} are replaced by the arguments;
/// an argument that is itself a message key (e.g. {label}) is translated first. Missing texts come from English,
/// at last the key itself is shown. Numbers and dates are formatted with the locale (package intl).
library;

import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';

import '../modules/module_spec.dart' show Message;

const supportedLanguages = ['de', 'en'];
const localeOfLanguage = {'de': 'de_DE', 'en': 'en_GB'};

String systemLanguage() {
  final l = PlatformDispatcher.instance.locale.languageCode;
  return supportedLanguages.contains(l) ? l : 'en';
}

class Strings {
  final String language;
  final Map<String, String> _texts;
  final Strings? fallback;

  Strings(this.language, this._texts, {this.fallback});

  static Future<Strings> load(String language) async {
    Future<Map<String, String>> read(String lang) async =>
        (jsonDecode(await rootBundle.loadString('assets/i18n/$lang.json')) as Map<String, dynamic>)
            .cast<String, String>();
    final en = Strings('en', await read('en'));
    return language == 'en' ? en : Strings(language, await read(language), fallback: en);
  }

  String get locale => localeOfLanguage[language]!;

  bool has(String key) => _texts.containsKey(key) || (fallback?.has(key) ?? false);

  String call(String key, [Map<String, Object> args = const {}]) {
    var text = _texts[key] ?? fallback?._texts[key] ?? key;
    args.forEach((name, value) {
      final v = value is String && has(value) ? call(value) : _format(value);
      text = text.replaceAll('{$name}', v);
    });
    return text;
  }

  String message(Message m) => call(m.key, m.args);

  //*********** numbers ************

  String _format(Object value) => value is num ? number(value) : '$value';

  /// number with up to [decimals] decimals - without grouping for input fields
  String number(num v, {int decimals = 2, bool grouping = true}) {
    final f = NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: decimals);
    f.minimumFractionDigits = 0;
    if (!grouping) f.turnOffGrouping();
    return f.format(v);
  }

  String fixed(num v, int decimals) =>
      NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: decimals).format(v);

  /// number entered by the user in the format of the language, null if it is not a number
  num? parse(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      return NumberFormat.decimalPattern(locale).parse(t);
    } on FormatException {
      return null;
    }
  }
}
