/// A small writer of Excel files (.xlsx, Office Open XML) - sheets of rows with texts and numbers, bold rows.
///
/// An .xlsx file is a zip of XML files: the workbook, its sheets, the styles (normal, bold) and their relations.
/// Texts are written inline (no shared strings), numbers as numbers - Excel shows them in the format of its language.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

class XlsxSheet {
  final String name;
  final List<List<Object?>> rows = []; // a cell: String, num or null (empty)
  final Set<int> boldRows = {};
  XlsxSheet(this.name);

  void add(List<Object?> row, {bool bold = false}) {
    if (bold) boldRows.add(rows.length);
    rows.add(row);
  }

  void empty() => rows.add(const []);
}

/// the file of the sheets - a sheet without rows is left out
Uint8List encodeXlsx(List<XlsxSheet> sheets) {
  final used = sheets.where((s) => s.rows.isNotEmpty).toList();
  final names = _sheetNames([for (final s in used) s.name]);
  final archive = Archive();
  void file(String name, String content) => archive.add(ArchiveFile.string(name, content));

  file('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${[for (var i = 1; i <= used.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join('\n')}
</Types>''');
  file('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
  file('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
${[for (var i = 1; i <= used.length; i++) '<sheet name="${_xml(names[i - 1])}" sheetId="$i" r:id="rId$i"/>'].join('\n')}
</sheets>
</workbook>''');
  file('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${[for (var i = 1; i <= used.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join('\n')}
<Relationship Id="rId${used.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
  // style 0: normal, 1: bold, 2: number with two decimals (#,##0.00), 3: bold number with two decimals
  file('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="4" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1"/></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''');
  for (final (i, s) in used.indexed) {
    file('xl/worksheets/sheet${i + 1}.xml', _sheet(s));
  }
  return ZipEncoder().encodeBytes(archive);
}

String _sheet(XlsxSheet s) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  // the width of a column: its longest text (the first column of key-value sheets included), at most 60
  final widths = <int, int>{};
  for (final row in s.rows) {
    for (final (c, v) in row.indexed) {
      final len = v is num
          ? _number(v).length
          : '${v ?? ''}'.split('\n').fold(0, (m, l) => l.length > m ? l.length : m);
      if (len > (widths[c] ?? 0)) widths[c] = len;
    }
  }
  if (widths.isNotEmpty) {
    b.write('<cols>');
    for (final MapEntry(:key, :value) in widths.entries) {
      final w = (value + 2).clamp(6, 60);
      b.write('<col min="${key + 1}" max="${key + 1}" width="$w" customWidth="1"/>');
    }
    b.write('</cols>');
  }
  b.write('<sheetData>');
  for (final (r, row) in s.rows.indexed) {
    b.write('<row r="${r + 1}">');
    final bold = s.boldRows.contains(r);
    final style = bold ? ' s="1"' : '';
    for (final (c, v) in row.indexed) {
      if (v == null || (v is String && v.isEmpty)) continue;
      final ref = '${_column(c)}${r + 1}';
      if (v is num && v.isFinite) {
        // whole numbers as they are, the others shown with two decimals - the cell keeps the exact value
        final decimals = _number(v).contains('.') ? (bold ? ' s="3"' : ' s="2"') : style;
        b.write('<c r="$ref"$decimals><v>${_number(v)}</v></c>');
      } else {
        b.write('<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_xml('$v')}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

/// A, B, ..., Z, AA, AB, ...
String _column(int index) {
  var i = index + 1;
  var s = '';
  while (i > 0) {
    final m = (i - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    i = (i - 1) ~/ 26;
  }
  return s;
}

String _number(num v) => v is int || v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// names Excel accepts: at most 31 characters, without : \ / ? * [ ], unique
List<String> _sheetNames(List<String> names) {
  final out = <String>[];
  for (final n in names) {
    var name = n.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (name.isEmpty) name = 'Sheet';
    if (name.length > 31) name = name.substring(0, 31);
    var unique = name;
    for (var k = 2; out.any((o) => o.toLowerCase() == unique.toLowerCase()); k++) {
      final suffix = ' $k';
      unique = (name.length + suffix.length > 31 ? name.substring(0, 31 - suffix.length) : name) + suffix;
    }
    out.add(unique);
  }
  return out;
}
