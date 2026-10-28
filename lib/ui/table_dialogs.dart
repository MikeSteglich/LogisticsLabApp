/// Copy and paste of tables (model/table_io.dart): the copy into the clipboard, the dialog of a paste - its columns
/// assigned, checked and applied - and the coordinates of the nodes looked up from their addresses.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../model/table_io.dart';
import 'messages.dart';
import 'theme.dart';

/// the text into the clipboard - a note with the number of rows
Future<void> copyText(BuildContext context, AppState s, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  final rows = '\n'.allMatches(text).length;
  showNote(context, s.strings('ui.copy.done', {'n': rows}));
}

/// paste of nodes or edges - the text of the clipboard taken if it is a table
Future<void> showPasteDialog(BuildContext context, AppState s, TableKind kind) async {
  String text = '';
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final String t when t.contains('\t') || t.contains('\n')) text = t;
  } catch (_) {
    // the browser may refuse - then it is pasted into the field
  }
  if (!context.mounted) return;
  final result = await showDialog<ImportCheck>(
    context: context,
    builder: (c) => _PasteDialog(state: s, kind: kind, text: text),
  );
  if (result == null || !context.mounted) return;
  final t = s.strings;
  showNote(
    context,
    [
      t('ui.import.done', {'added': result.added, 'updated': result.updated}),
      if (result.errors.isNotEmpty) t('ui.import.skipped', {'n': result.errors.length}),
    ].join(' · '),
  );
}

class _PasteDialog extends StatefulWidget {
  final AppState state;
  final TableKind kind;
  final String text;
  const _PasteDialog({required this.state, required this.kind, required this.text});

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  late final _text = TextEditingController(text: widget.text);
  TableImport? _import;
  ImportCheck? _check;
  (int, int)? _progress; // addresses looked up: (done, total)
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    final text = _text.text;
    _import = text.trim().isEmpty ? null : TableImport(widget.state, widget.kind, text);
    _recheck();
  }

  void _recheck() => setState(() => _check = _import?.check());

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    _text.text = data?.text ?? '';
    _parse();
  }

  Future<void> _apply() async {
    final imp = _import;
    if (imp == null) return;
    setState(() => _progress = (0, _check?.toLocate.length ?? 0));
    final result = await imp.apply(
      progress: (done, total) {
        if (mounted) setState(() => _progress = (done, total));
      },
      cancelled: () => _cancelled,
    );
    if (mounted) Navigator.pop(context, result);
  }

  String _error(ImportError e) {
    final t = widget.state.strings;
    final text = t(e.key, e.args);
    return e.row == 0 ? text : t('ui.import.row', {'row': e.row, 'text': text});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = s.strings;
    final imp = _import;
    final check = _check;
    final nodes = widget.kind == TableKind.nodes;
    final busy = _progress != null;
    return AlertDialog(
      title: Text(t(nodes ? 'ui.import.nodes' : 'ui.import.edges')),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t(nodes ? 'ui.import.helpNodes' : 'ui.import.helpEdges'), style: Ui.small),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                enabled: !busy,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: t('ui.import.pasteHere'),
                  suffixIcon: IconButton(
                    tooltip: t('ui.import.fromClipboard'),
                    icon: const Icon(Icons.content_paste, size: 18),
                    onPressed: busy ? null : _paste,
                  ),
                ),
                onChanged: (_) => _parse(),
              ),
              if (imp != null && imp.width > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: imp.header,
                          onChanged: busy
                              ? null
                              : (v) {
                                  imp.header = v ?? false;
                                  _recheck();
                                },
                        ),
                        Text(t('ui.import.header'), style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    SegmentedButton<ImportMode>(
                      segments: [
                        ButtonSegment(value: ImportMode.add, label: Text(t('ui.import.add'))),
                        ButtonSegment(value: ImportMode.update, label: Text(t('ui.import.update'))),
                      ],
                      selected: {imp.mode},
                      onSelectionChanged: busy
                          ? null
                          : (v) {
                              imp.mode = v.first;
                              _recheck();
                            },
                    ),
                    // nodes without a column of their roles get this one
                    if (nodes && !imp.mapping.contains('roles') && imp.mode == ImportMode.add)
                      // a field as the others of the app - the role from the values of the row (supply, demand) or
                      // one role for all
                      SizedBox(
                        width: 320,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('role|${imp.role}|${imp.canDetectRoles}'),
                          initialValue: imp.role,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t('ui.import.role').replaceAll(RegExp(r'\s*:\s*$'), ''),
                            isDense: true,
                          ),
                          items: [
                            if (imp.canDetectRoles)
                              DropdownMenuItem(
                                value: TableImport.autoRole,
                                child: Text(t('ui.import.autoRole'), overflow: TextOverflow.ellipsis),
                              ),
                            for (final r in s.assignableRoles.isEmpty ? const ['customer'] : s.assignableRoles)
                              DropdownMenuItem(value: r, child: Text(t('role.$r'))),
                          ],
                          onChanged: busy
                              ? null
                              : (v) {
                                  imp.role = v;
                                  _recheck();
                                },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _Preview(state: s, import: imp, onChanged: busy ? null : _recheck),
                // without a column of the address: the columns it is made of
                if (nodes && !imp.mapping.contains('address')) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(t('ui.import.addressFrom'), style: const TextStyle(fontSize: 13)),
                      for (var i = 0; i < imp.width; i++)
                        FilterChip(
                          label: Text(imp.columnName(i), style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          selected: imp.addressParts.contains(i),
                          onSelected: busy
                              ? null
                              : (on) {
                                  imp.addressParts = on
                                      ? ([...imp.addressParts, i]..sort())
                                      : [
                                          for (final p in imp.addressParts)
                                            if (p != i) p,
                                        ];
                                  _recheck();
                                },
                        ),
                    ],
                  ),
                  if (imp.addressParts.isNotEmpty && imp.data.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        t('ui.import.addressExample', {'address': imp.composedAddress(imp.data.first)}),
                        style: Ui.small,
                      ),
                    ),
                ],
              ],
              if (check != null) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    t('ui.import.result', {'added': check.added, 'updated': check.updated}),
                    if (check.toLocate.isNotEmpty) t('ui.import.toLocate', {'n': check.toLocate.length}),
                    if (check.errors.isNotEmpty) t('ui.import.errors', {'n': check.errors.length}),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                for (final e in check.errors.take(8))
                  Text(_error(e), style: const TextStyle(fontSize: 12, color: Ui.warning)),
                if (check.errors.length > 8) Text('…', style: const TextStyle(fontSize: 12, color: Ui.warning)),
              ],
              if (_progress case (final done, final total) when total > 0) ...[
                const SizedBox(height: 12),
                Text(t('ui.geo.progress', {'done': done, 'total': total}), style: Ui.small),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: total == 0 ? null : done / total),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? () => _cancelled = true : () => Navigator.pop(context),
          child: Text(t(busy ? 'ui.geo.stop' : 'ui.cancel')),
        ),
        FilledButton(
          onPressed: busy || check == null || check.isEmpty ? null : _apply,
          child: Text(t('ui.import.apply')),
        ),
      ],
    );
  }
}

/// the first rows of the table - above every column the choice of its meaning
class _Preview extends StatelessWidget {
  final AppState state;
  final TableImport import;
  final VoidCallback? onChanged;
  const _Preview({required this.state, required this.import, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = state.strings;
    final imp = import;
    final shown = imp.rows.take(imp.header ? 6 : 5).toList();
    Widget cell(String text, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: head ? Ui.textSecondary : Ui.text,
          fontWeight: head ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Ui.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Ui.surfaceAlt),
              children: [
                for (var i = 0; i < imp.width; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: DropdownButton<String?>(
                      value: imp.mapping[i],
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(fontSize: 12, color: Ui.accentDark, fontWeight: FontWeight.w600),
                      items: [
                        DropdownMenuItem(value: null, child: Text(t('ui.import.ignore'))),
                        for (final c in imp.columns)
                          // every meaning only once
                          if (c.key == imp.mapping[i] || !imp.mapping.contains(c.key))
                            DropdownMenuItem(value: c.key, child: Text(t(c.label))),
                      ],
                      onChanged: onChanged == null
                          ? null
                          : (v) {
                              imp.mapping[i] = v;
                              onChanged!();
                            },
                    ),
                  ),
              ],
            ),
            for (final (r, row) in shown.indexed)
              TableRow(
                decoration: BoxDecoration(
                  border: const Border(top: BorderSide(color: Color(0xFFEEF0F3))),
                  color: r == 0 && imp.header ? Ui.surfaceAlt : null,
                ),
                children: [for (final c in row) cell(c, head: r == 0 && imp.header)],
              ),
          ],
        ),
      ),
    );
  }
}

/// the coordinates of the nodes of the list from their addresses - asked first, with progress and cancel
Future<void> locateAll(BuildContext context, AppState s) async {
  final t = s.strings;
  final nodes = [
    for (final n in s.filteredNodes)
      if ((n.address ?? '').trim().isNotEmpty) n,
  ];
  if (nodes.isEmpty) {
    showNote(context, t('ui.geo.noAddresses'));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t('ui.geo.allTitle')),
      content: Text(t('ui.geo.allText', {'n': nodes.length})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('ui.geo.allStart'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final progress = ValueNotifier<(int, int)>((0, nodes.length));
  var cancelled = false;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(t('ui.geo.allTitle')),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (_, p, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('ui.geo.progress', {'done': p.$1, 'total': p.$2})),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => cancelled = true, child: Text(t('ui.geo.stop')))],
    ),
  );
  final (found, missing) = await locateNodes(
    s,
    nodes,
    progress: (done, total) => progress.value = (done, total),
    cancelled: () => cancelled,
  );
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialog;
  progress.dispose();
  if (!context.mounted) return;
  showNote(
    context,
    [
      t('ui.geo.allDone', {'n': found}),
      if (missing.isNotEmpty) t('ui.geo.allMissing', {'names': missing.take(10).join(', ')}),
    ].join(' · '),
  );
}
