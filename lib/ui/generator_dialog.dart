/// Random problem for exercises: the problem type, the region (countries, section of the map), the number of nodes
/// per role and the means of their values - varied at random. The start value gives the same problem again.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../model/generator.dart';
import '../model/scenario.dart';
import '../modules/modules.dart';
import 'theme.dart';
import 'widgets.dart';

List<City>? _cities;

/// the cities of Europe - loaded once
Future<List<City>> loadCities() async => _cities ??= parseCities(await rootBundle.loadString('assets/data/cities.tsv'));

/// the generated scenario - null if cancelled
Future<Scenario?> showGeneratorDialog(BuildContext context, AppState state) async {
  final cities = await loadCities();
  if (!context.mounted) return null;
  return showDialog<Scenario>(
    context: context,
    builder: (_) => _GeneratorDialog(state: state, cities: cities),
  );
}

/// the settings stay for the next random problem of the session
String _type = 'tpp';
Set<String> _countries = {'DE'};
bool _inSection = false;
final _counts = <String, Map<String, int>>{}; // per problem type
final _means = <String, Map<String, num?>>{};
num _variation = 30;
bool _integer = true;
bool _cover = true;
int _commodities = 2;
num _vehicleCapacity = 100;
num? _costPerKm = 1;

class _GeneratorDialog extends StatefulWidget {
  final AppState state;
  final List<City> cities;
  const _GeneratorDialog({required this.state, required this.cities});

  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  int _seed = _newSeed();
  String? _error;

  static int _newSeed() => math.Random().nextInt(9000) + 1000;

  Strings get t => widget.state.strings;
  GeneratorPlan get _plan => GeneratorPlan.of(modules[_type]!);

  Map<String, int> get counts => _counts[_type] ??= {for (final g in _plan.groups) g.key: _plan.defaultCount(g)};

  Map<String, num?> get means => _means[_type] ??= {
    for (final g in _plan.groups)
      for (final f in g.fields) '${g.key}.${f.key}': _plan.defaultMean(f),
    for (final f in _plan.edgeFields) 'edge.${f.key}': _plan.defaultMean(f),
  };

  List<String> get _allCountries {
    final codes = {for (final c in widget.cities) c.country}.toList();
    return codes..sort((a, b) => _country(a).compareTo(_country(b)));
  }

  String _country(String code) => t.has('country.$code') ? t('country.$code') : code;

  (LatLng, LatLng)? get _section => _inSection ? widget.state.mapSection : null;

  int get _available => citiesIn(widget.cities, _countries, _section).length;

  void _generate() {
    final plan = _plan;
    try {
      final s = generate(
        GeneratorSettings(
          type: _type,
          countries: _countries,
          section: _section,
          counts: counts,
          means: means,
          variation: _variation / 100,
          integer: _integer,
          cover: _cover,
          commodities: _commodities,
          vehicleCapacity: _vehicleCapacity,
          costPerKm: plan.withCosts ? _costPerKm : null,
          seed: _seed,
        ),
        widget.cities,
        name: t('ui.generator.scenarioName', {'type': t(plan.spec.label), 'seed': _seed}),
        problemName: t(plan.spec.label),
        networkName: t('ui.generator.network'),
        vehicleName: t('ui.generator.vehicle'),
        modeNames: (t('ui.generator.road'), t('ui.generator.rail')),
      );
      Navigator.pop(context, s);
    } on GeneratorException catch (e) {
      setState(() => _error = t(e.key, e.args));
    }
  }

  Future<void> _chooseCountries() async {
    final chosen = {..._countries};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t('ui.generator.countries')),
          content: SizedBox(
            width: 360,
            height: 420,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => set(() => chosen.addAll(_allCountries)),
                      child: Text(t('ui.generator.all')),
                    ),
                    TextButton(onPressed: () => set(chosen.clear), child: Text(t('ui.generator.none'))),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final code in _allCountries)
                        CheckboxListTile(
                          dense: true,
                          value: chosen.contains(code),
                          title: Text(_country(code)),
                          onChanged: (v) => set(() => v == true ? chosen.add(code) : chosen.remove(code)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('ui.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('ui.ok'))),
          ],
        ),
      ),
    );
    if (ok == true) setState(() => _countries = chosen);
  }

  Widget _number(String label, num? value, ValueChanged<num?> onChanged, {String? key, String? hint, int? decimals}) =>
      NumberField(
        key: ValueKey('$_type|${key ?? label}'),
        label: label,
        value: value,
        strings: t,
        hint: hint,
        decimals: decimals ?? 6,
        onChanged: (v) => setState(() {
          _error = null;
          onChanged(v);
        }),
      );

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final regionText = _countries.isEmpty
        ? t('ui.generator.allCountries')
        : ([for (final c in _countries) _country(c)]..sort()).join(', ');
    return AlertDialog(
      title: Text(t('ui.generator.title')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldLabel(t('ui.generator.type')),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                items: [
                  for (final types in problemTypesByGroup.values)
                    for (final type in types)
                      if (modules[type] case final m?) DropdownMenuItem(value: type, child: Text(t(m.label))),
                ],
                onChanged: (v) => setState(() {
                  _type = v ?? _type;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              Text(t('ui.generator.region'), style: Ui.title),
              const SizedBox(height: Ui.gap),
              Row(
                children: [
                  Expanded(child: Text(regionText, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: _chooseCountries, child: Text(t('ui.generator.chooseCountries'))),
                ],
              ),
              if (widget.state.mapSection != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _inSection,
                  title: Text(t('ui.generator.inSection')),
                  onChanged: (v) => setState(() {
                    _inSection = v ?? false;
                    _error = null;
                  }),
                ),
              Text(t('ui.generator.available', {'n': _available}), style: Ui.small),
              const SizedBox(height: 16),
              Text(t('ui.generator.nodesAndValues'), style: Ui.title),
              const SizedBox(height: Ui.gap),
              for (final g in plan.groups)
                // pickup and delivery: as many delivery nodes as pickups
                if (!(plan.paired && g.key == 'destinations'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Ui.gap),
                    child: FieldGrid(
                      children: [
                        _number(
                          t('ui.generator.count', {'nodes': t(g.label)}),
                          counts[g.key],
                          (v) => counts[g.key] = math.max(0, v?.round() ?? 0),
                          key: '${g.key}|count',
                          decimals: 0,
                        ),
                        for (final f in g.fields)
                          _number(
                            t('ui.generator.mean', {'field': t(f.label)}),
                            means['${g.key}.${f.key}'],
                            (v) => means['${g.key}.${f.key}'] = v,
                            key: '${g.key}.${f.key}',
                            hint: t('ui.generator.notSet'),
                          ),
                      ],
                    ),
                  ),
              if (plan.withNetwork && plan.edgeFields.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Ui.gap),
                  child: FieldGrid(
                    children: [
                      for (final f in plan.edgeFields)
                        _number(
                          t('ui.generator.edgeMean', {'field': t(f.label)}),
                          means['edge.${f.key}'],
                          (v) => means['edge.${f.key}'] = v,
                          key: 'edge.${f.key}',
                          hint: t('ui.generator.notSet'),
                        ),
                    ],
                  ),
                ),
              FieldGrid(
                children: [
                  if (plan.spec.usesCommodities)
                    _number(
                      t('ui.commodities'),
                      _commodities,
                      (v) => _commodities = math.max(1, v?.round() ?? 1),
                      decimals: 0,
                    ),
                  if (plan.spec.usesVehicles)
                    _number(t('ui.generator.vehicleCapacity'), _vehicleCapacity, (v) => _vehicleCapacity = v ?? 100),
                  if (plan.withCosts) _number(t('field.costPerKm'), _costPerKm, (v) => _costPerKm = v, hint: '0'),
                  _number(t('ui.generator.variation'), _variation, (v) => _variation = (v ?? 0).clamp(0, 100)),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _integer,
                title: Text(t('ui.generator.integer')),
                onChanged: (v) => setState(() => _integer = v ?? true),
              ),
              if (plan.canCover)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _cover,
                  title: Text(t('ui.generator.cover')),
                  onChanged: (v) => setState(() => _cover = v ?? true),
                ),
              const SizedBox(height: Ui.gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 200,
                    child: NumberField(
                      key: ValueKey('seed|$_seed'),
                      label: t('ui.generator.seed'),
                      help: t('ui.generator.seed.help'),
                      value: _seed,
                      strings: t,
                      decimals: 0,
                      onChanged: (v) => _seed = v?.round() ?? _seed,
                    ),
                  ),
                  IconButton(
                    tooltip: t('ui.generator.newSeed'),
                    icon: const Icon(Icons.casino_outlined, size: 20),
                    onPressed: () => setState(() => _seed = _newSeed()),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: Ui.gap),
                Text(_error!, style: const TextStyle(color: Ui.error, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('ui.cancel'))),
        FilledButton(onPressed: _generate, child: Text(t('ui.generator.create'))),
      ],
    );
  }
}
