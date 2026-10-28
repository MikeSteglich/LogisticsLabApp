/// Main screen: header with problem chooser and toolbar, map and data area with a draggable divider, status bar.
library;

import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../modules/modules.dart';
import 'data_panel.dart';
import 'file_ops.dart';
import 'about_dialog.dart';
import 'help_dialog.dart';
import 'logo.dart';
import 'map_view.dart';
import 'messages.dart';
import 'new_window.dart';
import 'settings_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

/// solves the problem - an error or a problem without solution is shown in a dialog (and in the status bar)
Future<void> solve(BuildContext context, AppState s) async {
  await s.solve();
  if (!context.mounted) return;
  if (s.lastResult == 'cancelled') {
    showNote(context, s.strings('ui.solve.cancelled'));
  } else if (s.message != null) {
    await showError(context, s.strings, s.message!);
  }
}

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
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => solve(context, state),
      const SingleActivator(LogicalKeyboardKey.enter, control: true): () => solve(context, state),
      // help: cmd/ctrl + ? (the key of the keyboard layout) and F1
      const CharacterActivator('?', meta: true): () => showHelp(context, state),
      const CharacterActivator('?', control: true): () => showHelp(context, state),
      const SingleActivator(LogicalKeyboardKey.f1): () => showHelp(context, state),
      if (newWindowSupported) ...{
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true): () => _newWindow(context, state),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () => _newWindow(context, state),
      },
    };
    return _ExitGuard(
      state: state,
      files: files,
      child: _ListKeys(
        state: state,
        child: CallbackShortcuts(
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
                            second: DataPanel(
                              state: state,
                              onSaveSolution: files.saveSolution,
                              onExportSolution: files.exportSolution,
                            ),
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
                  // the files opened or saved last - name and folder
                  if (!kIsWeb)
                    SubmenuButton(
                      menuChildren: [
                        for (final path in s.recentFiles)
                          MenuItemButton(
                            onPressed: () => files.openRecent(path),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(path.split(RegExp(r'[/\\]')).last),
                                Text(_folder(path), style: Ui.small),
                              ],
                            ),
                          ),
                        if (s.recentFiles.isNotEmpty) ...[
                          const Divider(),
                          MenuItemButton(onPressed: s.clearRecent, child: Text(t('ui.recent.clear'))),
                        ],
                      ],
                      child: Text(t('ui.recent')),
                    ),
                  MenuItemButton(onPressed: files.importOld, child: Text(t('ui.import'))),
                  MenuItemButton(onPressed: files.openExample, child: Text(t('ui.example'))),
                  // a second instance of the app - e.g. two variants side by side
                  if (newWindowSupported)
                    MenuItemButton(
                      onPressed: () => _newWindow(context, s),
                      shortcut: defaultTargetPlatform == TargetPlatform.macOS
                          ? const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true)
                          : const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true),
                      child: Text(t('ui.newWindow')),
                    ),
                  MenuItemButton(
                    onPressed: s.solution?.results == null ? null : files.exportSolution,
                    child: Text(t('ui.export.menu')),
                  ),
                  const Divider(),
                  MenuItemButton(onPressed: () => showAbout(context, s), child: Text(t('ui.about.menu'))),
                ],
              ),
              sep,
              if (s.solving)
                // the optimisation runs: orange with a spinner - a click cancels it
                Tooltip(
                  message: t('ui.solvingCancel'),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Ui.warning, foregroundColor: Colors.white),
                    icon: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    label: Text(t('ui.cancel')),
                    onPressed: s.cancel,
                  ),
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(t('ui.solve')),
                  onPressed: s.spec == null ? null : () => solve(context, s),
                ),
              const SizedBox(width: 12),
              _LanguageToggle(state: s),
              IconButton(
                tooltip: t('ui.settings'),
                icon: const Icon(Icons.settings_outlined, size: 20),
                onPressed: () => showSettings(context, s),
              ),
              // the help - also cmd/ctrl + ? and F1
              IconButton(
                tooltip: '${t('ui.help.menu')} (${defaultTargetPlatform == TargetPlatform.macOS ? '⌘?' : 'F1'})',
                icon: const Icon(Icons.help_outline, size: 20),
                onPressed: () => showHelp(context, s),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// another instance of the app - an error (e.g. the program moved) as message
/// the folder of a file - the home folder as ~
String _folder(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  final folder = i <= 0 ? path : path.substring(0, i);
  final home = homeFolder;
  return home != null && home.isNotEmpty && folder.startsWith(home) ? '~${folder.substring(home.length)}' : folder;
}

Future<void> _newWindow(BuildContext context, AppState s) async {
  try {
    await openNewWindow();
  } catch (e) {
    if (context.mounted) await showError(context, s.strings, '$e');
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
          const Logo(size: 28),
          if (!compact) ...[
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // the name of the app is in the title of the window - here the file
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    file,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Text(state.dirty ? t('ui.modified') : t('ui.saved.state'), style: Ui.small),
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

/// language of the app: a small button with the code (DE, EN, ...) and a menu of the languages
class _LanguageToggle extends StatelessWidget {
  final AppState state;
  const _LanguageToggle({required this.state});

  @override
  Widget build(BuildContext context) => MenuAnchor(
    builder: (context, m, _) => Tooltip(
      message: state.strings('ui.language'),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: const Icon(Icons.language, size: 16),
        label: Text(state.strings.language.toUpperCase()),
        onPressed: () => m.isOpen ? m.close() : m.open(),
      ),
    ),
    menuChildren: [
      for (final l in supportedLanguages)
        MenuItemButton(
          leadingIcon: Icon(
            l == state.strings.language ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 16,
            color: l == state.strings.language ? Ui.accent : Ui.textSecondary,
          ),
          onPressed: () => state.setLanguage(l),
          child: Text(languageNames[l]!),
        ),
    ],
  );
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

/// asks before the app is closed with unsaved changes - Cmd+Q, the menu and the close button of the window
class _ExitGuard extends StatefulWidget {
  final AppState state;
  final FileOps files;
  final Widget child;
  const _ExitGuard({required this.state, required this.files, required this.child});

  @override
  State<_ExitGuard> createState() => _ExitGuardState();
}

class _ExitGuardState extends State<_ExitGuard> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onExitRequested: _exitRequested);
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _exitRequested() async {
    final s = widget.state;
    if (!s.dirty || !mounted) return AppExitResponse.exit;
    final t = s.strings;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('ui.quit.title', {'file': s.fileName ?? t('ui.untitled')})),
        content: Text(t('ui.quit.text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: Text(t('ui.cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: Text(t('ui.quit.discard'))),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(t('ui.quit.save'))),
        ],
      ),
    );
    switch (choice) {
      case 'discard':
        return AppExitResponse.exit;
      case 'save':
        await widget.files.save();
        return s.dirty ? AppExitResponse.cancel : AppExitResponse.exit; // not saved: the app stays
      default:
        return AppExitResponse.cancel;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// arrow keys up and down: the previous or next entry of the list of the tab - not while typing in a field or with a
/// dialog or menu open
class _ListKeys extends StatefulWidget {
  final AppState state;
  final Widget child;
  const _ListKeys({required this.state, required this.child});

  @override
  State<_ListKeys> createState() => _ListKeysState();
}

class _ListKeysState extends State<_ListKeys> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  bool _key(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final delta = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (delta == 0 || !mounted) return false;
    // a dialog, menu or dropdown on top
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    // typing in a field
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    widget.state.moveSelection(delta);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
