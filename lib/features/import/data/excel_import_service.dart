import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../core/database/app_database.dart';
import '../domain/import_models.dart';

class ExcelImportService {
  static const _aliases = <ImportField, Set<String>>{
    ImportField.korean: {'韩语单词', '韩语', '单词', '단어', 'word', 'korean'},
    ImportField.english: {'英文','英语','영어','english','englishword'},
    ImportField.meaningZh: {
      '中文释义',
      '中文',
      '释义',
      '뜻',
      'meaning',
      'meaningzh',
    },
    ImportField.baseForm: {'原形', '기본형', 'baseform'},
    ImportField.pronunciation: {'发音', '读音', '발음', 'pronunciation'},
    ImportField.partOfSpeech: {'词性', '품사', 'partofspeech', 'pos'},
    ImportField.exampleKo: {'韩语例句', '例句', '예문', 'exampleko'},
    ImportField.exampleZh: {'中文例句', '例句翻译', '번역', 'examplezh'},
    ImportField.topikLevel: {'topik等级', 'topik', '等级', '급수'},
    ImportField.category: {'分类', '类别', '분류', 'category'},
    ImportField.tags: {'标签', '태그', 'tags'},
    ImportField.note: {'备注', '메모', 'note'},
    ImportField.hanja: {'汉字词', '한자', 'hanja'},
    ImportField.etymology: {'词源', '어원', 'etymology'},
  };

  List<String> sheetNames(Uint8List bytes) => Excel.decodeBytes(bytes).tables.keys.toList();
  List<String> sheetHeaders(Uint8List bytes, String name) => Excel.decodeBytes(bytes).tables[name]!.rows.first.map(_cellText).toList();

  ParsedWorkbook parseFirstSheet(Uint8List bytes, {String? sheetName, Map<ImportField,int>? mappingOverride, bool allSheets=false}) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('Excel 中没有可读取的工作表。');
    }
    if(allSheets) {
      final drafts=<WordDraft>[];var invalid=0;
      for(final name in workbook.tables.keys) {
        try { final sheet=parseFirstSheet(bytes,sheetName:name);drafts.addAll(sheet.drafts);invalid+=sheet.invalidRows; }
        on FormatException { invalid+=workbook.tables[name]!.rows.length; }
      }
      return ParsedWorkbook(sheetName:'全部工作表',headers:const [],mapping:const {},drafts:drafts,invalidRows:invalid);
    }
    final entry = sheetName==null ? workbook.tables.entries.first : workbook.tables.entries.firstWhere((s)=>s.key==sheetName);
    final rows = entry.value.rows;
    if (rows.isEmpty) {
      throw const FormatException('工作表为空。');
    }
    final headers = rows.first.map(_cellText).toList(growable: false);
    final mapping = mappingOverride ?? guessMapping(headers);
    if (!mapping.containsKey(ImportField.korean) && !mapping.containsKey(ImportField.english)) {
      throw const FormatException('请手动选择韩语或英文单词列。');
    }

    final drafts = <WordDraft>[];
    var invalidRows = 0;
    for (final row in rows.skip(1)) {
      final korean = _value(row, mapping[ImportField.korean]);
      final english = _value(row, mapping[ImportField.english]);
      final meaning = _value(row, mapping[ImportField.meaningZh]);
      if (korean.isEmpty && english.isEmpty && meaning.isEmpty) continue;
      if (korean.isEmpty && english.isEmpty) {
        invalidRows++;
        continue;
      }
      drafts.add(
        WordDraft(
          korean: korean.isNotEmpty && english.isNotEmpty && korean != english ? '$english / $korean' : korean.isNotEmpty ? korean : english,
          meaningZh: meaning.isEmpty ? '原表未提供中文释义' : meaning,
          baseForm: _value(row, mapping[ImportField.baseForm]),
          pronunciation: _optional(row, mapping[ImportField.pronunciation]),
          partOfSpeech: _optional(row, mapping[ImportField.partOfSpeech]),
          exampleKo: _optional(row, mapping[ImportField.exampleKo]),
          exampleZh: _optional(row, mapping[ImportField.exampleZh]),
          topikLevel: _optional(row, mapping[ImportField.topikLevel]),
          category: _optional(row, mapping[ImportField.category]),
          tags: [if(_optional(row,mapping[ImportField.tags])!=null)_optional(row,mapping[ImportField.tags])!,
            if(meaning.isEmpty)korean.isNotEmpty&&english.isNotEmpty?'英韩配对':korean.isNotEmpty?'仅韩文':'仅英文'].join(', '),
          note: _optional(row, mapping[ImportField.note]),
          hanja: _optional(row, mapping[ImportField.hanja]),
          etymology: _optional(row, mapping[ImportField.etymology]),
        ),
      );
    }
    return ParsedWorkbook(
      sheetName: entry.key,
      headers: headers,
      mapping: mapping,
      drafts: drafts,
      invalidRows: invalidRows,
    );
  }

  Map<ImportField, int> guessMapping(List<String> headers) {
    final result = <ImportField, int>{};
    for (var index = 0; index < headers.length; index++) {
      final normalized = _normalizeHeader(headers[index]);
      for (final field in ImportField.values) {
        if (result.containsKey(field)) continue;
        final candidates = _aliases[field] ?? const <String>{};
        if (candidates.map(_normalizeHeader).contains(normalized)) {
          result[field] = index;
          break;
        }
      }
    }
    return result;
  }

  String _cellText(Data? cell) => cell?.value?.toString().trim() ?? '';

  String _value(List<Data?> row, int? index) {
    if (index == null || index >= row.length) return '';
    return _cellText(row[index]);
  }

  String? _optional(List<Data?> row, int? index) {
    final value = _value(row, index);
    return value.isEmpty ? null : value;
  }

  String _normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-（）()]'), '')
        .trim();
  }
}
