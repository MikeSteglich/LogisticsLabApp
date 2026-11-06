/// Help texts of the fields: for the problem type, its group or in general - beside the label of every kind of field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logisticslab_app/i18n/strings.dart';
import 'package:logisticslab_app/modules/modules.dart';
import 'package:logisticslab_app/ui/widgets.dart';

void main() {
  Future<String?> help(WidgetTester tester, FieldSpec f, ModuleSpec? module) async {
    final t = (await tester.runAsync(() => Strings.load('de')))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SpecField(spec: f, value: null, strings: t, module: module, onChanged: (_) {}),
        ),
      ),
    );
    final tips = tester.widgetList<Tooltip>(find.byType(Tooltip));
    return tips.isEmpty ? null : tips.first.message;
  }

  testWidgets('the help of the problem type, the group or the general one', (tester) async {
    const capacity = FieldSpec('capacity', FieldKind.unlimited, min: 0);
    expect(await help(tester, capacity, minCostFlowSpec), startsWith('Höchstmenge, die über die Kante'));
    expect(await help(tester, capacity, multiCommoditySpec), contains('Kapazitätseinheiten'));
    expect(await help(tester, capacity, vrpSpec), contains('Ladung eines Fahrzeugs')); // group routing
    const demand = FieldSpec('demand', FieldKind.number, min: 0);
    expect(await help(tester, demand, modules['pmedian']), contains('Bedarf des Kunden'));
    expect(await help(tester, demand, null), startsWith('Menge, die beim Nachfrager ankommt'));
  });

  testWidgets('choices and time windows: the help beside the label', (tester) async {
    expect(
      await help(tester, const FieldSpec('balance', FieldKind.choice, choices: ['auto', 'exact']), null),
      startsWith('automatisch:'),
    );
    expect(await help(tester, const FieldSpec('timeWindow', FieldKind.timeWindow), vrpSpec), contains('Uhrzeit'));
    expect(await help(tester, const FieldSpec('name', FieldKind.text), null), isNull);
  });
}
