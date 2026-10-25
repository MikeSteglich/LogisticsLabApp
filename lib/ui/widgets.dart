/// Common building blocks: split view, number field and the fields generated from a FieldSpec.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../model/clock.dart';
import '../model/scenario.dart';
import '../modules/modules.dart';
import 'theme.dart';

//*************** split view: map | data area ************************************

/// Two areas with a draggable divider - side by side (axis horizontal) or one above the other.
/// ratio is the part of the first child; double click on the divider restores the default.
class SplitView extends StatelessWidget {
  final Axis axis;
  final double ratio;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onReset;
  final String semanticLabel;
  final Widget first;
  final Widget second;

  const SplitView({
    super.key,
    required this.axis,
    required this.ratio,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
    required this.semanticLabel,
    required this.first,
    required this.second,
  });

  static const handle = 12.0;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, c) {
        final total = (horizontal ? c.maxWidth : c.maxHeight) - handle;
        final a = (total * ratio).floorToDouble();
        void drag(Offset local) => onChanged(((horizontal ? local.dx : local.dy) - handle / 2) / total);
        final divider = Semantics(
          label: semanticLabel,
          slider: true,
          value: '${(ratio * 100).round()} %',
          increasedValue: '${(ratio * 100 + 5).round()} %',
          decreasedValue: '${(ratio * 100 - 5).round()} %',
          onIncrease: () => onChangeEnd(ratio + 0.05),
          onDecrease: () => onChangeEnd(ratio - 0.05),
          child: MouseRegion(
            cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: onReset,
              onPanUpdate: (d) {
                final box = context.findRenderObject() as RenderBox;
                drag(box.globalToLocal(d.globalPosition));
              },
              onPanEnd: (_) => onChangeEnd(ratio),
              child: SizedBox(
                width: horizontal ? handle : null,
                height: horizontal ? null : handle,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (horizontal) const VerticalDivider(width: 1) else const Divider(height: 1),
                    Container(
                      width: horizontal ? 6 : 36,
                      height: horizontal ? 36 : 6,
                      decoration: BoxDecoration(color: Ui.inputBorder, borderRadius: BorderRadius.circular(3)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final children = [
          SizedBox(width: horizontal ? a : null, height: horizontal ? null : a, child: first),
          divider,
          Expanded(child: second),
        ];
        return horizontal ? Row(children: children) : Column(children: children);
      },
    );
  }
}

//*************** fields ************************************

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Ui.textMuted),
    ),
  );
}

/// Text field that keeps its own controller - the value is taken on every change (onChanged).
class TextValueField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool readOnly;
  final String? error;
  final String? hint;

  const TextValueField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
    this.error,
    this.hint,
  });

  @override
  State<TextValueField> createState() => _TextValueFieldState();
}

class _TextValueFieldState extends State<TextValueField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(TextValueField old) {
    super.didUpdateWidget(old);
    // changed from outside, e.g. the position set on the map
    if (widget.value != old.value && widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(widget.label),
      TextField(
        controller: _c,
        readOnly: widget.readOnly,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.next,
        onEditingComplete: () {}, // enter: the next field (onSubmitted) instead of the default
        onSubmitted: (_) => focusNextField(context),
        decoration: InputDecoration(
          errorText: widget.error,
          hintText: widget.hint,
          fillColor: widget.readOnly ? Ui.surfaceAlt : null,
        ),
      ),
    ],
  );
}

/// enter in a field: the next input field of the mask - buttons, chips and dropdowns between them are skipped
void focusNextField(BuildContext context) {
  bool isField(FocusNode? n) {
    final c = n?.context;
    return c != null && (c.widget is EditableText || c.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  final start = FocusManager.instance.primaryFocus;
  if (start == null) return;
  // the focus changes only after this frame - the order of the traversal gives the next field at once
  final order = _FieldOrder().of(FocusScope.of(context).traversalDescendants, start);
  final i = order.indexOf(start);
  for (final n in [...order.skip(i + 1), ...order.take(i < 0 ? 0 : i)]) {
    if (isField(n) && n.canRequestFocus) return n.requestFocus();
  }
}

/// the reading order of the focus traversal (as the app) - for focusNextField
class _FieldOrder extends ReadingOrderTraversalPolicy {
  List<FocusNode> of(Iterable<FocusNode> nodes, FocusNode current) => sortDescendants(nodes, current).toList();
}

/// Number in the format of the language - empty is null (with hint, e.g. "unlimited").
class NumberField extends StatefulWidget {
  final String label;
  final num? value;
  final ValueChanged<num?> onChanged;
  final Strings strings;
  final int decimals;
  final String? hint;
  final String? unit;
  final String? help; // shown as tooltip of an info symbol beside the label
  final Message? Function(num?)? check;
  final String Function(num?)? format; // other text than a number, e.g. a time of the day
  final num? Function(String)? parse;
  final String? invalid; // message key of a text parse cannot read - default error.number

  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.strings,
    this.decimals = 6,
    this.hint,
    this.unit,
    this.help,
    this.check,
    this.format,
    this.parse,
    this.invalid,
  });

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _c = TextEditingController(text: _text(widget.value));
  String? _error;

  String _text(num? v) => widget.format != null
      ? widget.format!(v)
      : (v == null ? '' : widget.strings.number(v, decimals: widget.decimals, grouping: false));

  num? _parse(String t) => widget.parse != null ? widget.parse!(t) : widget.strings.parse(t);

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    final current = _parse(_c.text);
    if (widget.value != current && widget.value != old.value) {
      _c.text = _text(widget.value);
      _error = null;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _changed(String t) {
    final v = _parse(t);
    String? error;
    if (t.trim().isNotEmpty && v == null) {
      error = widget.strings(widget.invalid ?? 'error.number', {'label': widget.label});
    } else {
      final m = widget.check?.call(v);
      if (m != null) error = widget.strings.message(m);
    }
    setState(() => _error = error);
    if (error == null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(child: FieldLabel(widget.unit == null ? widget.label : '${widget.label} (${widget.unit})')),
          if (widget.help != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Tooltip(
                message: widget.help!,
                child: const Icon(Icons.info_outline, size: 14, color: Ui.textSecondary),
              ),
            ),
        ],
      ),
      TextField(
        controller: _c,
        onChanged: _changed,
        textInputAction: TextInputAction.next,
        onEditingComplete: () {}, // enter: the next field (onSubmitted) instead of the default
        onSubmitted: (_) => focusNextField(context),
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        // digits and the signs of a number - a time of the day also with its colon
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(widget.parse != null ? r'[0-9:.\s]' : r'[0-9.,\-\s]')),
        ],
        style: const TextStyle(fontFeatures: Ui.tabular),
        decoration: InputDecoration(errorText: _error, hintText: widget.hint, errorMaxLines: 2),
      ),
    ],
  );
}

/// Field of a FieldSpec - value and change go to the map [values] (node attributes or parameters).
class SpecField extends StatelessWidget {
  final FieldSpec spec;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final Strings strings;
  final Scenario? scenario; // nodes, commodities and modes for the fields that refer to them
  final VoidCallback? onEditRecords; // commodities, modes: opens their list (parameters tab)

  const SpecField({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    required this.strings,
    this.scenario,
    this.onEditRecords,
  });

  /// unit of the field - @time and @distance: the units of the scenario
  String? _unit(String? unit) => switch (unit) {
    '@time' => scenario?.units['time'] as String?,
    '@distance' => scenario?.units['distance'] as String?,
    _ => unit,
  };

  /// label of a field with commodities or modes - with a link to their list
  Widget _recordsLabel(String label) => Row(
    children: [
      Expanded(child: FieldLabel(label)),
      if (onEditRecords != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: onEditRecords,
            child: Text(
              '${strings(spec.kind == FieldKind.modes ? 'ui.modes' : 'ui.commodities')} ${strings('ui.records.edit')}',
              style: const TextStyle(fontSize: 12, color: Ui.accent),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final label = s(spec.label);
    switch (spec.kind) {
      case FieldKind.boolean:
        return InkWell(
          onTap: () => onChanged(!(value == true)),
          borderRadius: BorderRadius.circular(Ui.radius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Checkbox(value: value == true, onChanged: (v) => onChanged(v ?? false)),
                Flexible(child: Text(label, style: const TextStyle(fontSize: 14))),
                if (s.has(spec.help)) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: s(spec.help),
                    child: const Icon(Icons.info_outline, size: 16, color: Ui.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        );
      case FieldKind.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(label),
            DropdownButtonFormField<String?>(
              initialValue: spec.choices.contains(value) ? value as String : null,
              isExpanded: true,
              hint: s.has(spec.help) ? Text(s(spec.help), overflow: TextOverflow.ellipsis) : null,
              items: [
                if (!spec.required && spec.defaultValue == null)
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('–', style: TextStyle(color: Ui.textSecondary)),
                  ),
                for (final c in spec.choices) DropdownMenuItem<String?>(value: c, child: Text(s(spec.choiceLabel(c)))),
              ],
              onChanged: onChanged,
            ),
          ],
        );
      case FieldKind.text:
        return TextValueField(label: label, value: value as String? ?? '', onChanged: onChanged);
      case FieldKind.node:
        final nodes = scenario?.nodes ?? const <Node>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(label),
            DropdownButtonFormField<String?>(
              initialValue: nodes.any((n) => n.id == value) ? value as String : null,
              isExpanded: true,
              items: [
                for (final n in nodes) DropdownMenuItem<String?>(value: n.id, child: Text('${n.id} · ${n.name}')),
              ],
              onChanged: onChanged,
            ),
          ],
        );
      case FieldKind.commodities:
        // a number per commodity of the scenario - empty: 0 (supplies, demands) or 1 (capacity factors)
        final values = (value as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final commodities = scenario?.commodities ?? const <Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _recordsLabel(label),
            if (commodities.isEmpty) Text(s('ui.commodities.none'), style: Ui.small),
            Wrap(
              spacing: Ui.gap,
              runSpacing: 8,
              children: [
                for (final c in commodities)
                  SizedBox(
                    width: 150,
                    child: NumberField(
                      key: ValueKey('${spec.key}|${c['id']}'),
                      label: Scenario.recordName(c),
                      value: values[c['id']] as num?,
                      strings: s,
                      check: (v) => v != null && v < 0 ? Message('error.min', {'label': spec.label, 'min': 0}) : null,
                      onChanged: (v) {
                        final next = {...values};
                        if (v == null) {
                          next.remove(c['id']);
                        } else {
                          next[c['id'] as String] = v;
                        }
                        onChanged(next.isEmpty ? null : next);
                      },
                    ),
                  ),
              ],
            ),
          ],
        );
      case FieldKind.modes:
        // modes allowed at the edge - no map: all modes of the scenario; the values of a mode at the edge are kept
        final allowed = (value as Map?)?.cast<String, dynamic>();
        final modes = scenario?.modes ?? const <Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _recordsLabel(label),
            if (modes.isEmpty) Text(s('ui.modes.none'), style: Ui.small),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in modes)
                  FilterChip(
                    label: Text(Scenario.recordName(m)),
                    selected: allowed == null || allowed.containsKey(m['id']),
                    onSelected: (on) {
                      final next = <String, dynamic>{
                        for (final x in modes)
                          if (allowed == null || allowed.containsKey(x['id']))
                            x['id'] as String: allowed?[x['id']] ?? {},
                      };
                      if (on) {
                        next[m['id'] as String] = allowed?[m['id']] ?? <String, dynamic>{};
                      } else {
                        next.remove(m['id']);
                      }
                      onChanged(
                        next.length == modes.length && next.values.every((v) => (v as Map).isEmpty) ? null : next,
                      );
                    },
                  ),
              ],
            ),
          ],
        );
      case FieldKind.timeWindow:
        // earliest and latest as times of the day - both empty: no time window
        final tw = (value as List?) ?? const [null, null];
        final clock = Clock(scenario?.units['time'] as String? ?? 'min');
        void set(int i, num? v) {
          final next = [...tw]..[i] = v;
          onChanged(next.every((x) => x == null) ? null : next);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(label),
            Row(
              children: [
                for (final (i, key) in const [(0, 'ui.timeWindow.from'), (1, 'ui.timeWindow.to')]) ...[
                  if (i == 1) const SizedBox(width: Ui.gap),
                  Expanded(
                    child: NumberField(
                      key: ValueKey('${spec.key}|$i'),
                      label: s(key),
                      value: tw[i] as num?,
                      strings: s,
                      hint: i == 1 ? s('hint.open') : s('hint.clock'),
                      format: clock.format,
                      parse: clock.parse,
                      invalid: 'error.clock',
                      check: (v) {
                        final next = [...tw]..[i] = v;
                        return spec.validate(next.every((x) => x == null) ? null : next);
                      },
                      onChanged: (v) => set(i, v),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      case FieldKind.number || FieldKind.integer || FieldKind.unlimited:
        return NumberField(
          label: label,
          value: value is num ? value as num : null,
          strings: s,
          unit: _unit(spec.unit),
          decimals: spec.kind == FieldKind.integer ? 0 : 6,
          hint: spec.hint != null ? s(spec.hint!) : (spec.kind == FieldKind.unlimited ? s('hint.unlimited') : null),
          help: s.has(spec.help) ? s(spec.help) : null,
          check: (v) => spec.validate(v),
          onChanged: onChanged,
        );
    }
  }
}

/// Fields in a grid with [columns] columns - booleans over the whole width.
/// fields over the whole width of a FieldGrid
const _wide = {FieldKind.boolean, FieldKind.commodities, FieldKind.modes};

class FieldGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  const FieldGrid({super.key, required this.children, this.columns = 2});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth < 360 ? 1 : columns;
      final w = (c.maxWidth - Ui.gap * (cols - 1)) / cols;
      return Wrap(
        spacing: Ui.gap,
        runSpacing: Ui.gap,
        children: [
          for (final child in children)
            SizedBox(width: child is SpecField && _wide.contains(child.spec.kind) ? c.maxWidth : w, child: child),
        ],
      );
    },
  );
}

/// A table over the whole available width: its columns as wide as their content and the rest shared out - wider
/// than the space it scrolls sideways with a scroll bar.
class WideTable extends StatefulWidget {
  final List<TableRow> rows;
  final Map<int, TableColumnWidth> columnWidths;
  const WideTable({super.key, required this.rows, this.columnWidths = const {}});

  @override
  State<WideTable> createState() => _WideTableState();
}

class _WideTableState extends State<WideTable> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          // at least the whole width - the table shares the rest out among its columns
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: Table(
            columnWidths: widget.columnWidths,
            defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
            children: widget.rows,
          ),
        ),
      ),
    ),
  );
}

class Section extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Section({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      border: Border.all(color: Ui.border),
      borderRadius: BorderRadius.circular(Ui.radius),
      color: Ui.surface,
    ),
    child: child,
  );
}

/// Badge with the problem type, e.g. TPP.
class TypeBadge extends StatelessWidget {
  final String text;
  const TypeBadge(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Ui.accentLight, borderRadius: BorderRadius.circular(4)),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: Ui.accentDark),
    ),
  );
}

//*************** list and mask ************************************

/// Header (fixed), list and mask with their own scrolling and a draggable divider between them - the mask stays in
/// view with long lists. [selectedKey] marks the selected row: the list scrolls to it when [selected] changes.
class ListAndMask extends StatefulWidget {
  final Widget header;
  final Widget list;
  final Widget mask;
  final Object? selected;
  final GlobalKey selectedKey;
  final double ratio;
  final ValueChanged<double> onRatio;
  final ValueChanged<double> onRatioEnd;
  final VoidCallback onRatioReset;
  final String semanticLabel;

  const ListAndMask({
    super.key,
    required this.header,
    required this.list,
    required this.mask,
    required this.selected,
    required this.selectedKey,
    required this.ratio,
    required this.onRatio,
    required this.onRatioEnd,
    required this.onRatioReset,
    required this.semanticLabel,
  });

  @override
  State<ListAndMask> createState() => _ListAndMaskState();
}

class _ListAndMaskState extends State<ListAndMask> {
  @override
  void initState() {
    super.initState();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(ListAndMask old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) _scrollToSelected();
  }

  /// e.g. a node chosen on the map - its row comes into view
  void _scrollToSelected() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = widget.selectedKey.currentContext;
    if (c != null && c.mounted) {
      Scrollable.ensureVisible(
        c,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: widget.header),
      Expanded(
        child: SplitView(
          axis: Axis.vertical,
          ratio: widget.ratio,
          semanticLabel: widget.semanticLabel,
          onChanged: widget.onRatio,
          onChangeEnd: widget.onRatioEnd,
          onReset: widget.onRatioReset,
          first: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: widget.list),
          second: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: widget.mask),
        ),
      ),
    ],
  );
}
