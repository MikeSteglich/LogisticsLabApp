/// Settings: language and computing (local solver or server).
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/backend.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showSettings(BuildContext context, AppState state) => showDialog(
  context: context,
  builder: (_) => _SettingsDialog(state: state),
);

class _SettingsDialog extends StatefulWidget {
  final AppState state;
  const _SettingsDialog({required this.state});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late BackendSettings b = widget.state.backendSettings;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = s.strings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => AlertDialog(
        title: Text(t('ui.settings')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldLabel(t('ui.language')),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'de', label: Text('Deutsch')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {t.language},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => s.setLanguage(v.first),
                ),
                const SizedBox(height: 20),
                FieldLabel(t('ui.backend.title')),
                if (!localBackendSupported)
                  Text(t('ui.backend.webOnlyRemote'), style: Ui.small)
                else
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(t('ui.backend.local'))),
                      ButtonSegment(value: true, label: Text(t('ui.backend.remote'))),
                    ],
                    selected: {b.remote},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => b = b.copyWith(remote: v.first)),
                  ),
                const SizedBox(height: 14),
                if (!b.remote && localBackendSupported) ...[
                  Text(t('ui.backend.localHelp'), style: Ui.small),
                  const SizedBox(height: 10),
                  TextValueField(
                    label: t('ui.backend.executable'),
                    value: b.executable,
                    onChanged: (v) => b = b.copyWith(executable: v.trim()),
                  ),
                  const SizedBox(height: 10),
                  TextValueField(
                    label: t('ui.backend.arguments'),
                    value: b.arguments.join(' '),
                    hint: '-m logisticsLabCore.stdio',
                    onChanged: (v) =>
                        b = b.copyWith(arguments: v.trim().isEmpty ? const [] : v.trim().split(RegExp(r'\s+'))),
                  ),
                  const SizedBox(height: 10),
                  TextValueField(
                    label: t('ui.backend.workDir'),
                    value: b.workingDirectory,
                    onChanged: (v) => b = b.copyWith(workingDirectory: v.trim()),
                  ),
                ] else ...[
                  TextValueField(
                    label: t('ui.backend.url'),
                    value: b.url,
                    onChanged: (v) => b = b.copyWith(url: v.trim()),
                  ),
                  const SizedBox(height: 10),
                  TextValueField(
                    label: t('ui.backend.apiKey'),
                    value: b.apiKey,
                    onChanged: (v) => b = b.copyWith(apiKey: v.trim()),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('ui.cancel'))),
          FilledButton(
            onPressed: () {
              s.setBackendSettings(b);
              Navigator.pop(context);
            },
            child: Text(t('ui.ok')),
          ),
        ],
      ),
    );
  }
}
