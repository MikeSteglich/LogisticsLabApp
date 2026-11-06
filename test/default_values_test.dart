/// A value given in advance (a default) disappears when the user clicks into the field - left without an input it is
/// back, the model keeps it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logisticslab_app/i18n/strings.dart';
import 'package:logisticslab_app/ui/widgets.dart';

void main() {
  testWidgets('a field with a default is emptied on the focus, one without keeps its text', (tester) async {
    final t = (await tester.runAsync(() => Strings.load('de')))!;
    num? a, b;
    String? name;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              NumberField(label: 'A', value: 100, isDefault: true, strings: t, onChanged: (v) => a = v),
              NumberField(label: 'B', value: 100, strings: t, onChanged: (v) => b = v),
              TextValueField(label: 'N', value: 'Variante 1', isDefault: true, onChanged: (v) => name = v),
            ],
          ),
        ),
      ),
    );
    final fields = find.byType(TextField);
    String text(int i) => tester.widget<TextField>(fields.at(i)).controller!.text;

    await tester.tap(fields.at(0));
    await tester.pump();
    expect(text(0), '');
    expect(find.text('100'), findsNWidgets(2)); // the hint and field B
    expect(a, isNull); // the model keeps the default

    // left without an input: the default is back
    await tester.tap(fields.at(1));
    await tester.pump();
    expect(text(0), '100');
    expect(text(1), '100'); // no default - unchanged
    expect(b, isNull);

    // clicked again and typed: the input stays
    await tester.tap(fields.at(0));
    await tester.pump();
    await tester.enterText(fields.at(0), '5');
    expect(a, 5);
    await tester.tap(fields.at(1));
    await tester.pump();
    expect(text(0), '5');
    await tester.tap(fields.at(0));
    await tester.pump();
    expect(text(0), '5'); // no longer a default

    await tester.tap(fields.at(2));
    await tester.pump();
    expect(text(2), '');
    await tester.enterText(fields.at(2), 'Hoch');
    expect(name, 'Hoch');
  });
}
