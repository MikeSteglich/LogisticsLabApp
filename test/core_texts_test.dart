/// The texts of the core in the language of the app: warnings by their code, messages of the jobs by their wording.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:logisticslab_app/i18n/strings.dart';
import 'package:logisticslab_app/model/core_texts.dart';

Strings _strings(String language) {
  Map<String, String> read(String l) =>
      (jsonDecode(File('assets/i18n/$l.json').readAsStringSync()) as Map).cast<String, String>();
  final en = Strings('en', read('en'));
  return language == 'en' ? en : Strings(language, read(language), fallback: en);
}

void main() {
  final de = _strings('de');

  test('warnings by their code - attributes and problem types by their names in the app', () {
    final doc = {
      'warnings': [
        'costFactor is not supported by contpcentre and is ignored',
        'delivery nodes without a pickup: A, B',
      ],
      'warningCodes': [
        {'code': 'ignored', 'attribute': 'costFactor', 'type': 'contpcentre'},
        {'code': 'deliveriesWithoutPickup', 'nodes': 'A, B'},
      ],
    };
    expect(coreWarnings(de, doc), [
      'Kostenfaktor wird bei ${de('module.contpcentre')} nicht berücksichtigt',
      'Zustellorte ohne Abholung: A, B',
    ]);
    // without codes (older solutions) or an unknown code: the text of the core
    expect(coreWarnings(de, {'warnings': doc['warnings']}), doc['warnings']);
    expect(
      coreWarnings(de, {
        'warnings': ['new warning'],
        'warningCodes': [
          {'code': 'unknown'},
        ],
      }),
      ['new warning'],
    );
  });

  test('messages of the jobs - with their numbers', () {
    expect(
      coreMessage(de, 'time limit exceeded - the problem has been stopped after 360s'),
      'Zeitlimit überschritten – das Problem wurde nach 360 s abgebrochen',
    );
    expect(coreMessage(de, 'No solution has been found'), 'Es wurde keine Lösung gefunden');
    expect(coreMessage(de, 'the solver process does not start'), 'Der Rechenprozess startet nicht');
    expect(coreMessage(de, 'problem x: no vehicles'), 'problem x: no vehicles'); // unknown: as it is
  });

  test('every code and message in all languages', () {
    final keys = [
      for (final k in (jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map).keys)
        if ('$k'.startsWith('core.')) '$k',
    ];
    expect(keys.length, greaterThan(15));
    for (final l in ['de', 'es', 'fr']) {
      final texts = (jsonDecode(File('assets/i18n/$l.json').readAsStringSync()) as Map);
      expect(keys.where((k) => !texts.containsKey(k)), isEmpty, reason: l);
    }
  });
}
