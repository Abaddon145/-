import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/import/data/excel_import_service.dart';

Uint8List workbook() {
  final zip = Archive();
  final files = {
    'xl/workbook.xml': '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="空白页" r:id="r1"/><sheet name="词汇整理" r:id="r2"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="/xl/worksheets/sheet2.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml': '<worksheet><sheetData/></worksheet>',
    // Vocabulary reading must not fail on styles produced by Excel/WPS.
    'xl/styles.xml': '<styleSheet><numFmts><numFmt numFmtId="0" formatCode="General"/></numFmts></styleSheet>',
    'xl/sharedStrings.xml': '<sst><si><t>英语 / 韩语</t></si><si><t>中文</t></si><si><r><t>steel roll</t></r><r><t> / 스틸 롤</t></r></si></sst>',
    'xl/worksheets/sheet2.xml': '''<worksheet><sheetData>
      <row r="2"><c r="A2" t="inlineStr"><is><t>工业词汇清单</t></is></c></row>
      <row r="4"><c r="A4" t="s"><v>0</v></c><c r="C4" t="s"><v>1</v></c></row>
      <row r="5"><c r="A5" t="s"><v>2</v></c><c r="C5" t="inlineStr"><is><t>钢辊</t></is></c></row>
      <row r="6"><c r="A6" t="inlineStr"><is><t>curl</t></is></c></row>
      <row r="7"><c r="C7" t="inlineStr"><is><t>只有中文</t></is></c></row>
      </sheetData></worksheet>''',
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    zip.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip)!);
}

void main() {
  test('blank first sheet title row mixed header sparse cells and rich strings work', () {
    final service = ExcelImportService();
    final bytes = workbook();
    expect(service.sheetNames(bytes), ['词汇整理']);
    expect(service.sheetHeaders(bytes, '词汇整理'), ['英语 / 韩语', '', '中文']);
    final parsed = service.parseFirstSheet(bytes);
    expect(parsed.drafts.map((word) => word.korean), ['steel roll / 스틸 롤', 'curl']);
    expect(parsed.drafts.first.meaningZh, '钢辊');
    expect(parsed.drafts.last.meaningZh, '原表未提供中文释义');
    expect(parsed.drafts.last.tags, '仅英文');
    expect(parsed.invalidRows, 1);
    expect(service.parseFirstSheet(bytes, allSheets: true).drafts, hasLength(2));
  });
  test('malformed files and empty downloads produce actionable errors', () {
    final service = ExcelImportService();
    expect(() => service.sheetNames(Uint8List(0)), throwsFormatException);
    expect(() => service.sheetNames(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
  test('decoded workbook imports into library and reimport reuses existing entries', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final parsed = ExcelImportService().parseFirstSheet(workbook());
    final bookId = await db.createWordBook(name: parsed.sheetName, sourceFileName: '词汇.xlsx');
    final first = await db.importWords(wordBookId: bookId, drafts: parsed.drafts, source: '词汇.xlsx');
    expect(first.inserted, 2);
    final second = await db.importWords(wordBookId: bookId, drafts: parsed.drafts, source: '词汇.xlsx');
    expect(second.inserted, 0);
    expect(second.reused, 2);
    expect(await db.searchLibraryWords(query: '', filter: LibraryFilter.all), hasLength(2));
  });
}
