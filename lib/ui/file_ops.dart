/// Open and save scenario files (.llab) and solutions (.llsol) - file dialogs on the desktop, download in the browser.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_state.dart';
import '../model/scenario.dart';
import '../modules/modules.dart';

const _llab = XTypeGroup(
  label: 'LogisticsLab',
  extensions: ['llab'],
  uniformTypeIdentifiers: ['public.json', 'public.data'],
);
const _old = XTypeGroup(
  label: 'LogisticsLab (alt)',
  extensions: [...AppState.oldFormats, 'TPPX', 'TSPX', 'CLPX', 'DLPX', 'NWFX', 'VRPX'],
  uniformTypeIdentifiers: ['public.data', 'public.plain-text'],
);
const _llsol = XTypeGroup(label: 'LogisticsLab-Lösung', extensions: ['llsol']);

class FileOps {
  final BuildContext context;
  final AppState state;
  FileOps(this.context, this.state);

  void _snack(String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<bool> _discardChanges() async {
    if (!state.dirty) return true;
    final t = state.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t('ui.discard')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('ui.discardYes'))),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> newScenario() async {
    if (!await _discardChanges()) return;
    final s = Scenario.empty();
    s.addProblem('tpp', state.strings(tppSpec.label), tppSpec.defaultParameters());
    state.openScenario(s);
  }

  Future<void> open() async {
    if (!await _discardChanges()) return;
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [_llab, _old]);
    } catch (e) {
      _snack('$e');
      return;
    }
    if (file == null) return;
    // an old file is imported
    if (AppState.isOldFile(file.name)) return _import(file);
    try {
      state.openScenario(Scenario.parse(await file.readAsString()), name: file.name, path: kIsWeb ? null : file.path);
    } on Exception catch (e) {
      _snack(state.strings('ui.error.open', {'msg': '$e'}));
    }
  }

  /// old LogisticsLab file (TPPX, CLPX, ...) - converted by the core into a scenario
  Future<void> importOld() async {
    if (!await _discardChanges()) return;
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [_old]);
    } catch (e) {
      _snack('$e');
      return;
    }
    if (file != null) await _import(file);
  }

  Future<void> _import(XFile file) async {
    final t = state.strings;
    final bytes = await file.readAsBytes();
    // the old files are UTF-8 or Latin-1
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    try {
      await state.importOld(file.name, text);
      _snack(t('ui.imported', {'file': file.name}));
    } catch (e) {
      _snack(t('ui.error.import', {'file': file.name, 'msg': '$e'}));
    }
  }

  Future<void> openExample() async {
    if (!await _discardChanges()) return;
    final text = await rootBundle.loadString('assets/examples/brandenburg.llab');
    state.openScenario(Scenario.parse(text), name: 'brandenburg.llab');
  }

  Future<void> save({bool saveAs = false}) async {
    final name = state.fileName ?? '${state.scenario.id}.llab';
    final path = await _write(
      state.scenario.toText(),
      name,
      _llab,
      saveAs || state.filePath == null ? null : state.filePath,
    );
    if (path == null) return;
    state.saved(name: path.split(RegExp(r'[/\\]')).last, path: kIsWeb ? null : path);
    _snack(state.strings('ui.saved', {'file': state.fileName!}));
  }

  Future<void> saveSolution() async {
    final sol = state.solution;
    if (sol == null) return;
    final base = (state.fileName ?? state.scenario.id).replaceAll(RegExp(r'\.llab$'), '');
    final text = '${const JsonEncoder.withIndent('  ').convert(sol.document)}\n';
    final path = await _write(text, '$base.llsol', _llsol, null);
    if (path != null) _snack(state.strings('ui.saved', {'file': path.split(RegExp(r'[/\\]')).last}));
  }

  /// writes the text - path null: asks for the file (desktop) or downloads it (browser); returns the path or name
  Future<String?> _write(String text, String name, XTypeGroup type, String? path) async {
    final data = Uint8List.fromList(utf8.encode(text));
    try {
      if (kIsWeb) {
        await XFile.fromData(data, name: name, mimeType: 'application/json').saveTo(name);
        return name;
      }
      path ??= (await getSaveLocation(suggestedName: name, acceptedTypeGroups: [type]))?.path;
      if (path == null) return null;
      await XFile.fromData(data, name: name, mimeType: 'application/json').saveTo(path);
      return path;
    } catch (e) {
      _snack('$e');
      return null;
    }
  }
}
