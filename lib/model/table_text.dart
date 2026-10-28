/// Tables as text of the clipboard - as Excel, Numbers, LibreOffice and Google Sheets copy and paste them.
///
/// Cells separated by tabs, rows by line breaks; a cell with a tab, a line break or a quote is quoted ("a ""b"""),
/// quotes inside doubled. Without a tab in the text it is read as CSV with semicolons or commas.
library;

/// the rows of the text - empty rows at the end left out, every row as long as the longest
List<List<String>> parseTable(String text) {
  final t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final sep = t.contains('\t')
      ? '\t'
      : (';'.allMatches(t).length >= ','.allMatches(t).length && t.contains(';')
            ? ';'
            : (t.contains(',') ? ',' : '\t'));
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false, atStart = true;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"' && atStart) {
      quoted = true;
      atStart = false;
    } else if (c == sep) {
      row.add(cell.toString().trim());
      cell.clear();
      atStart = true;
    } else if (c == '\n') {
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
      atStart = true;
    } else {
      cell.write(c);
      if (c != ' ') atStart = false;
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  while (rows.isNotEmpty && rows.last.every((c) => c.isEmpty)) {
    rows.removeLast();
  }
  final width = rows.fold(0, (m, r) => r.length > m ? r.length : m);
  return [
    for (final r in rows) [...r, for (var i = r.length; i < width; i++) ''],
  ];
}

/// the text of the rows for the clipboard - Excel takes it as cells
String tableText(List<List<String>> rows) => '${rows.map((r) => r.map(_quote).join('\t')).join('\n')}\n';

String _quote(String c) => c.contains(RegExp('[\t\n"]')) ? '"${c.replaceAll('"', '""')}"' : c;

/// a number as it is written in a table: 1234,5 or 1.234,5 (decimal comma) or 1234.5 or 1,234.5 - with spaces,
/// a unit or % behind it; null if it is no number
num? parseNumber(String text, {bool decimalComma = true}) {
  var s = text.trim().replaceAll(RegExp(r'[\s  ]'), '');
  s = s.replaceFirst(RegExp(r'(%|€|[a-zA-Z]+)$'), '');
  if (s.isEmpty) return null;
  s = s.replaceAll('−', '-');
  final comma = s.contains(','), dot = s.contains('.');
  if (comma && dot) {
    // the last of both is the decimal separator
    final decimal = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.';
    s = s.replaceAll(decimal == ',' ? '.' : ',', '').replaceAll(',', '.');
  } else if (comma) {
    // 1,234 with decimal point: a thousand - else a decimal comma
    s = !decimalComma && RegExp(r'^-?\d{1,3}(,\d{3})+$').hasMatch(s) ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  } else if (dot && decimalComma && RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', ''); // 1.234 with decimal comma: a thousand
  }
  final v = num.tryParse(s);
  if (v == null || !v.isFinite) return null;
  return v == v.roundToDouble() && !s.contains('.') ? v.toInt() : v;
}

/// a header or a value for comparisons: lower case, umlauts and accents folded, only letters and digits
String normalize(String s) {
  const fold = {
    'ä': 'a',
    'ö': 'o',
    'ü': 'u',
    'ß': 'ss',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'á': 'a',
    'à': 'a',
    'ó': 'o',
    'ò': 'o',
    'í': 'i',
    'ú': 'u',
    'ñ': 'n',
    'ç': 'c',
    'â': 'a',
    'î': 'i',
    'ô': 'o',
    'û': 'u',
  };
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final f = fold[c] ?? c;
    if (RegExp(r'[a-z0-9]').hasMatch(f)) b.write(f);
  }
  return b.toString();
}
