/// About dialog: logo, version, credits of the data and the software used, thanks.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'logo.dart';
import 'theme.dart';

/// name and version of the app - the version is the same as in pubspec.yaml (test/about_test.dart checks it).
/// The successor of LogisticsLab 5 starts at 1.0.0 - the name tells them apart.
const appName = 'LogisticsLab Studio';
const appVersion = '1.0.0';

Future<void> showAbout(BuildContext context, AppState state) {
  final t = state.strings;
  Widget credit(String what, String who) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(what, style: const TextStyle(fontSize: 13, color: Ui.textSecondary)),
        ),
        Expanded(child: SelectableText(who, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Logo(size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(appName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        Text(t('ui.about.version', {'version': appVersion}), style: Ui.small),
                        const SizedBox(height: 4),
                        Text(t('ui.about.tagline'), style: const TextStyle(fontSize: 13, color: Ui.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(t('ui.about.credits').toUpperCase(), style: Ui.sectionLabel),
              const SizedBox(height: 8),
              credit(t('ui.about.mapData'), '© ${t('ui.osm.contributors')}, ODbL – openstreetmap.org/copyright'),
              credit(t('ui.about.tiles'), 'OpenStreetMap Foundation – tile.openstreetmap.org'),
              credit(t('ui.about.routing'), 'openrouteservice (HeiGIT, Heidelberg) – ${t('ui.about.thServers')}'),
              credit(t('ui.about.geocoding'), 'Photon (komoot), Nominatim (OpenStreetMap Foundation)'),
              credit(t('ui.about.optimisation'), 'CMPL (TH Wildau), HiGHS, Google OR-Tools'),
              credit(t('ui.about.software'), 'Flutter, flutter_map (Fleaflet), pyLogisticsLab'),
              const SizedBox(height: 14),
              Text(t('ui.about.thanksTitle').toUpperCase(), style: Ui.sectionLabel),
              const SizedBox(height: 8),
              Text(t('ui.about.thanks'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 18),
              Text(t('ui.about.successor'), style: Ui.small),
              const SizedBox(height: 6),
              const Text(
                '© 2026 Mike Steglich, Technische Hochschule Wildau · LGPL-3.0',
                style: TextStyle(fontSize: 12, color: Ui.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(t('ui.close')))],
    ),
  );
}
