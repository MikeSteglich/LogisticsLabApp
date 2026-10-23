/// Main screen: header with problem chooser and toolbar, map and data area with a draggable divider, status bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../modules/modules.dart';
import 'data_panel.dart';
import 'file_ops.dart';
import 'map_view.dart';
import 'settings_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class MainScreen extends StatelessWidget {
  final AppState state;
  const MainScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final files = FileOps(context, state);
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true): files.open,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): files.open,
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): files.save,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): files.save,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): state.solve,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): state.solve,
    };
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(state: state, files: files),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth >= 900;
                      return SplitView(
                        axis: wide ? Axis.horizontal : Axis.vertical,
                        ratio: state.splitRatio,
                        semanticLabel: state.strings('ui.split'),
                        onChanged: state.setSplitRatio,
                        onChangeEnd: (v) => state.setSplitRatio(v, save: true),
                        onReset: () => state.setSplitRatio(AppState.defaultSplitRatio, save: true),
                        first: MapView(state: state),
                        second: DataPanel(state: state, onSaveSolution: files.saveSolution),
                      );
                    },
                  ),
                ),
                _StatusBar(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

//*************** header ************************************

class _Header extends StatelessWidget {
  final AppState state;
  final FileOps files;
  const _Header({required this.state, required this.files});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 1100; // buttons with icon only
        Widget tool(IconData icon, String label, VoidCallback? onPressed) => compact
            ? IconButton(tooltip: label, icon: Icon(icon, size: 20), onPressed: onPressed)
            : TextButton.icon(icon: Icon(icon, size: 18), label: Text(label), onPressed: onPressed);
        const sep = SizedBox(height: 28, child: VerticalDivider(width: 12));
        return Container(
          decoration: const BoxDecoration(
            color: Ui.surface,
            border: Border(bottom: BorderSide(color: Ui.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              _Logo(state: s, compact: c.maxWidth < 700),
              sep,
              _ProblemChooser(state: s),
              sep,
              tool(Icons.note_add_outlined, t('ui.new'), files.newScenario),
              tool(Icons.folder_open_outlined, t('ui.open'), files.open),
              tool(Icons.save_outlined, t('ui.save'), files.save),
              MenuAnchor(
                builder: (context, m, _) => IconButton(
                  tooltip: t('ui.saveAs'),
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onPressed: () => m.isOpen ? m.close() : m.open(),
                ),
                menuChildren: [
                  MenuItemButton(onPressed: () => files.save(saveAs: true), child: Text(t('ui.saveAs'))),
                  MenuItemButton(onPressed: files.openExample, child: Text(t('ui.example'))),
                ],
              ),
              sep,
              if (s.solving)
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(t('ui.cancel')),
                  onPressed: s.jobId == null ? null : s.cancel,
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(t('ui.solve')),
                  onPressed: s.spec == null ? null : s.solve,
                ),
              const SizedBox(width: 12),
              _LanguageToggle(state: s),
              _BackendChip(state: s),
              IconButton(
                tooltip: t('ui.settings'),
                icon: const Icon(Icons.settings_outlined, size: 20),
                onPressed: () => showSettings(context, s),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Logo extends StatelessWidget {
  final AppState state;
  final bool compact;
  const _Logo({required this.state, required this.compact});

  @override
  Widget build(BuildContext context) {
    final t = state.strings;
    final file = state.fileName ?? t('ui.untitled');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Ui.minTarget),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: Ui.accent, borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.hub_outlined, size: 16, color: Colors.white),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LogisticsLab', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    state.dirty ? '$file · ${t('ui.modified')}' : file,
                    overflow: TextOverflow.ellipsis,
                    style: Ui.small,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// one button with the name and the type of the problem - the menu has the problems of the file and new problems
class _ProblemChooser extends StatelessWidget {
  final AppState state;
  const _ProblemChooser({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final p = s.problem;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      builder: (context, m, _) => Semantics(
        label: t('ui.chooseProblem'),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, Ui.minTarget)),
          onPressed: () => m.isOpen ? m.close() : m.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  p?.name ?? t('ui.noProblem'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (p != null) ...[const SizedBox(width: 8), TypeBadge(t('module.${p.type}.short'))],
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
      menuChildren: [
        _menuLabel(t('ui.problemsIn', {'file': s.fileName ?? t('ui.untitled')})),
        for (final q in s.scenario.problems)
          MenuItemButton(
            onPressed: () => s.chooseProblem(q.name),
            leadingIcon: Icon(
              q.name == s.problemName ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: q.name == s.problemName ? Ui.accent : Ui.textSecondary,
            ),
            trailingIcon: TypeBadge(t('module.${q.type}.short')),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
              child: Text(q.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        const Divider(),
        _menuLabel(t('ui.newProblem')),
        for (final MapEntry(key: group, value: types) in problemTypesByGroup.entries)
          SubmenuButton(
            menuChildren: [
              for (final type in types)
                MenuItemButton(
                  onPressed: modules.containsKey(type) ? () => s.newProblem(type) : null,
                  child: Tooltip(
                    message: modules.containsKey(type) ? '' : t('ui.notYet', {'type': 'module.$type'}),
                    child: Text(t('module.$type')),
                  ),
                ),
            ],
            child: Text(t('group.${group.name}')),
          ),
      ],
    );
  }

  static Widget _menuLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Text(text.toUpperCase(), style: Ui.sectionLabel),
  );
}

class _LanguageToggle extends StatelessWidget {
  final AppState state;
  const _LanguageToggle({required this.state});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: state.strings('ui.language'),
    child: SegmentedButton<String>(
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: 'de', label: Text('DE')),
        ButtonSegment(value: 'en', label: Text('EN')),
      ],
      selected: {state.strings.language},
      showSelectedIcon: false,
      onSelectionChanged: (v) => state.setLanguage(v.first),
    ),
  );
}

class _BackendChip extends StatelessWidget {
  final AppState state;
  const _BackendChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.strings;
    final b = state.backendSettings;
    final label = b.remote ? '${t('ui.backend.remote')}: ${Uri.tryParse(b.url)?.host ?? b.url}' : t('ui.backend.local');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ActionChip(
        avatar: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: b.remote ? Ui.accent : Ui.ok, borderRadius: BorderRadius.circular(4)),
        ),
        label: Text(label),
        onPressed: () => showSettings(context, state),
      ),
    );
  }
}

//*************** status bar ************************************

class _StatusBar extends StatelessWidget {
  final AppState state;
  const _StatusBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    final t = s.strings;
    final sol = s.solution;
    final items = <Widget>[];
    Color dot = Ui.textSecondary;
    String text;
    if (s.solving) {
      dot = Ui.accent;
      text = t(s.status == 'starting' ? 'ui.status.starting' : 'ui.status.${s.status}');
      items.add(const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (sol != null) {
      dot = sol.status == 'solution' ? (s.solutionIsStale ? Ui.warning : Ui.ok) : Ui.error;
      final time = sol.results?['solvingTime'];
      text =
          t('ui.status.${sol.status}') +
          (time is num ? ' · ${t('ui.status.in', {'time': '${t.fixed(time, 2)} s'})}' : '');
    } else {
      text = t('ui.sol.none');
    }
    final objVal = sol?.results?['objVal'];
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: Ui.surface,
        border: Border(top: BorderSide(color: Ui.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items.isEmpty)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(4)),
                )
              else
                ...items,
              const SizedBox(width: 6),
              Text(text, style: Ui.small),
            ],
          ),
          if (objVal is num && !s.solving) Text('${t('ui.sol.objVal')} ${t.fixed(objVal, 2)}', style: Ui.small),
          if (s.message != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SelectableText(s.message!, maxLines: 2, style: const TextStyle(fontSize: 12, color: Ui.error)),
            ),
          Text(t(s.scenario.usesRoads ? 'ui.edges.osm' : 'ui.edges.beeline'), style: Ui.small),
          Text(t('ui.nodes.count', {'n': s.scenario.nodes.length}), style: Ui.small),
        ],
      ),
    );
  }
}
