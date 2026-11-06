/// A value given in advance (a default) is replaced by the first input - not added to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logisticslab_app/i18n/strings.dart';
import 'package:logisticslab_app/ui/widgets.dart';

void main() {
  test('the typed text replaces the default, a backspace empties it, the cursor alone keeps it', () {
    TextEditingValue edit(String old, String next) =>
        ReplaceDefault(true).formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: next));
    expect(edit('100', '1005').text, '5'); // typed at the end
    expect(edit('100', '7100').text, '7'); // at the start
    expect(edit('100', '10').text, ''); // backspace
    expect(edit('Variante 1', 'Variante 1H').text, 'H');
    final f = ReplaceDefault(true);
    expect(f.formatEditUpdate(const TextEditingValue(text: '1'), const TextEditingValue(text: '1')).text, '1');
    expect(f.active, isTrue); // only the cursor moved
    expect(f.formatEditUpdate(const TextEditingValue(text: '1'), const TextEditingValue(text: '12')).text, '2');
    // afterwards a normal field
    expect(f.formatEditUpdate(const TextEditingValue(text: '2'), const TextEditingValue(text: '23')).text, '23');
  });

  testWidgets('a number field with a default: the first input replaces it, one without keeps adding', (tester) async {
    final t = (await tester.runAsync(() => Strings.load('de')))!;
    num? a, b;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              NumberField(label: 'A', value: 100, isDefault: true, strings: t, onChanged: (v) => a = v),
              NumberField(label: 'B', value: 100, strings: t, onChanged: (v) => b = v),
            ],
          ),
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.tap(fields.at(0));
    await tester.enterText(fields.at(0), '1005');
    expect(a, 5);
    await tester.enterText(fields.at(0), '58');
    expect(a, 58);
    await tester.tap(fields.at(1));
    await tester.enterText(fields.at(1), '1005');
    expect(b, 1005);
  });
}
