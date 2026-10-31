/// About dialog: logo, version, credits of the data and the software used, thanks.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'logo.dart';
import 'theme.dart';

/// name and version of the app - the version is the same as in pubspec.yaml (test/about_test.dart checks it).
/// The successor of LogisticsLab 5 starts at 1.0.0 - the name tells them apart.
const appName = 'LogisticsLab Studio';
const appVersion = '1.0.1';

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
              Text(t('ui.about.authors').toUpperCase(), style: Ui.sectionLabel),
              const SizedBox(height: 8),
              credit(t('ui.about.author'), 'Mike Steglich'),
              credit(t('ui.about.coAuthor'), 'Claude (Anthropic)'),
              const SizedBox(height: 14),
              Text(t('ui.about.credits').toUpperCase(), style: Ui.sectionLabel),
              const SizedBox(height: 8),
              credit(t('ui.about.mapData'), '© ${t('ui.osm.contributors')}, ODbL – openstreetmap.org/copyright'),
              credit(t('ui.about.tiles'), 'OpenStreetMap Foundation – tile.openstreetmap.org'),
              // the software with its licence
              credit(
                t('ui.about.routing'),
                'openrouteservice (HeiGIT, Heidelberg), GPL-3.0 – ${t('ui.about.thServers')}',
              ),
              credit(
                t('ui.about.geocoding'),
                'Photon (komoot), Apache-2.0 · Nominatim (OpenStreetMap Foundation), GPL',
              ),
              credit(
                t('ui.about.optimisation'),
                'CMPL (TH Wildau), GPL-3.0 · HiGHS, MIT · Google OR-Tools, Apache-2.0',
              ),
              credit(
                t('ui.about.software'),
                'Flutter, BSD-3-Clause · flutter_map (Fleaflet), BSD-3-Clause · pyLogisticsLab',
              ),
              // the source code of the free software (AGPL) - also for the users of the web app
              credit(t('ui.about.source'), 'github.com/MikeSteglich/LogisticsLabApp · pyLogisticsLab'),
              const SizedBox(height: 14),
              Text(t('ui.about.thanksTitle').toUpperCase(), style: Ui.sectionLabel),
              const SizedBox(height: 8),
              Text(t('ui.about.thanks'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 18),
              Text(t('ui.about.successor'), style: Ui.small),
              const SizedBox(height: 6),
              const Text(
                '© 2026 Mike Steglich, Technische Hochschule Wildau · AGPL-3.0-or-later',
                style: TextStyle(fontSize: 12, color: Ui.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // the licences of all packages of the app - collected by Flutter
        TextButton(
          onPressed: () => showLicensePage(
            context: c,
            applicationName: appName,
            applicationVersion: appVersion,
            applicationIcon: const Padding(padding: EdgeInsets.all(8), child: Logo(size: 48)),
          ),
          child: Text(t('ui.about.licenses')),
        ),
        FilledButton(onPressed: () => Navigator.pop(c), child: Text(t('ui.close'))),
      ],
    ),
  );
}
