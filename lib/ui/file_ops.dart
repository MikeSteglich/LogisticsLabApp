/// Open and save scenario files (.llab) and solutions (.llsol) - file dialogs on the desktop, download in the browser.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app_log.dart';
import '../app_state.dart';
import '../backend/backend.dart';
import '../model/scenario.dart';
import '../model/solution_export.dart';
import 'messages.dart';

// macOS: the types of the app (Info.plist) - the save panel knows the extension and does not add it again
const _llab = XTypeGroup(
  label: 'LogisticsLab',
  extensions: ['llab'],
  uniformTypeIdentifiers: ['de.th-wildau.logisticslab.llab'],
);
const _old = XTypeGroup(
  label: 'LogisticsLab (alt)',
  extensions: [...AppState.oldFormats, 'TPPX', 'TSPX', 'CLPX', 'DLPX', 'NWFX', 'VRPX'],
);
const _llsol = XTypeGroup(
  label: 'LogisticsLab-Lösung',
  extensions: ['llsol'],
  uniformTypeIdentifiers: ['de.th-wildau.logisticslab.llsol'],
);
const _xlsx = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

class FileOps {
  final BuildContext context;
  final AppState state;
  FileOps(this.context, this.state);

  void _snack(String text) => showNote(context, text);

  Future<void> _error(String text) => showError(context, state.strings, text);

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
    // without a problem - it is chosen in the problem menu (new problem)
    state.openScenario(Scenario.empty());
  }

  Future<void> open() async {
    if (!await _discardChanges()) return;
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [_llab, _old]);
    } catch (e) {
      await _error('$e');
      return;
    }
    if (file == null) return;
    // an old file is imported
    if (AppState.isOldFile(file.name)) return _import(file);
    try {
      state.openScenario(Scenario.parse(await file.readAsString()), name: file.name, path: kIsWeb ? null : file.path);
    } on Exception catch (e) {
      await _error(state.strings('ui.error.open', {'msg': '$e'}));
    }
  }

  /// a file by its path - of the list of the recent ones or opened in the Finder or Explorer (an old file imported);
  /// one that is gone is taken off the list
  Future<void> openPath(String path) async {
    if (!await _discardChanges()) return;
    final file = XFile(path);
    if (AppState.isOldFile(path)) return _import(file);
    final String text;
    try {
      text = await file.readAsString();
    } catch (_) {
      state.removeRecent(path);
      await _error(state.strings('ui.recent.missing', {'file': path}));
      return;
    }
    try {
      state.openScenario(Scenario.parse(text), name: file.name, path: path);
    } on Exception catch (e) {
      await _error(state.strings('ui.error.open', {'msg': '$e'}));
    }
  }

  /// old LogisticsLab file (TPPX, CLPX, ...) - converted by the core into a scenario
  Future<void> importOld() async {
    if (!await _discardChanges()) return;
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [_old]);
    } catch (e) {
      await _error('$e');
      return;
    }
    if (file != null) await _import(file);
  }

  Future<void> _import(XFile file) async {
    final t = state.strings;
    appLog('import ${file.name}: chosen');
    // formats of LogisticsLab 4 (TPP, ...): planar coordinates and own matrices - not convertible
    final ext = file.name.split('.').last.toUpperCase();
    if (AppState.legacyFormats.contains(ext)) {
      await _error(t('ui.error.legacy', {'file': file.name, 'ext': ext}));
      return;
    }
    if (!context.mounted) return;
    // the dialog first - reading, starting the core and converting follow once it is shown
    try {
      final converted = await busy(
        context,
        t('ui.importing', {'file': file.name}),
        () async {
          appLog('import ${file.name}: dialog shown');
          final bytes = await file.readAsBytes();
          // the old files are UTF-8 or Latin-1
          String text;
          try {
            text = utf8.decode(bytes);
          } on FormatException {
            text = latin1.decode(bytes);
          }
          appLog('import ${file.name}: read ${bytes.length} bytes');
          final r = await state.convertOld(file.name, text);
          appLog('import ${file.name}: converted');
          return r;
        },
        cancelLabel: t('ui.cancel'),
        onCancel: state.resetBackend, // the solver may hang - the next request starts a new one
      );
      if (converted == null) return; // cancelled
      state.openImported(converted.$1, converted.$2);
      appLog('import ${file.name}: opened');
      _snack(t('ui.imported', {'file': file.name}));
    } on BackendException catch (e) {
      appLog('import ${file.name}: error $e');
      if (e.httpStatus == 504) unawaited(state.resetBackend()); // no answer - restart the solver
      await _error(e.outdated ? t('ui.error.outdated') : t('ui.error.import', {'file': file.name, 'msg': '$e'}));
    } catch (e) {
      appLog('import ${file.name}: error $e');
      await _error(t('ui.error.import', {'file': file.name, 'msg': '$e'}));
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

  /// the solution as Excel file - the tables of the solution tab (model/solution_export.dart)
  Future<void> exportSolution() async {
    if (state.solution == null) return;
    final base = (state.fileName ?? state.scenario.id).replaceAll(RegExp(r'\.llab$'), '');
    final problem = (state.problemName ?? '').replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
    final name = problem.isEmpty ? '$base.xlsx' : '$base - $problem.xlsx';
    final path = await _writeBytes(solutionXlsx(state), name, _xlsx, null, _xlsxMime);
    if (path != null) _snack(state.strings('ui.saved', {'file': path.split(RegExp(r'[/\\]')).last}));
  }

  /// the path with the extension exactly once - the save panel of macOS sometimes adds it to a name with another dot
  /// (drogma.dlpx.llab -> drogma.dlpx.llab.llab)
  static String withExtension(String path, String extension) =>
      '${path.replaceFirst(RegExp('(\\.${RegExp.escape(extension)})+\$', caseSensitive: false), '')}.$extension';

  /// writes the text - path null: asks for the file (desktop) or downloads it (browser); returns the path or name
  Future<String?> _write(String text, String name, XTypeGroup type, String? path) =>
      _writeBytes(Uint8List.fromList(utf8.encode(text)), name, type, path, 'application/json');

  Future<String?> _writeBytes(Uint8List data, String name, XTypeGroup type, String? path, String mime) async {
    try {
      if (kIsWeb) {
        await XFile.fromData(data, name: name, mimeType: mime).saveTo(name);
        return name;
      }
      path ??= (await getSaveLocation(suggestedName: name, acceptedTypeGroups: [type]))?.path;
      if (path == null) return null;
      path = withExtension(path, type.extensions!.first);
      await XFile.fromData(data, name: name, mimeType: mime).saveTo(path);
      return path;
    } catch (e) {
      await _error('$e');
      return null;
    }
  }
}
