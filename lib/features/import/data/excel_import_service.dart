import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../core/database/app_database.dart';
import '../domain/import_models.dart';

class ExcelImportService {
  static const _aliases = <ImportField, Set<String>>{
    ImportField.korean: {'韩语单词', '韩语', '单词', '단어', 'word', 'korean'},
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

  ParsedWorkbook parseFirstSheet(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('Excel 中没有可读取的工作表。');
    }
    final entry = workbook.tables.entries.first;
    final rows = entry.value.rows;
    if (rows.isEmpty) {
      throw const FormatException('工作表为空。');
    }
    final headers = rows.first.map(_cellText).toList(growable: false);
    final mapping = guessMapping(headers);
    if (!mapping.containsKey(ImportField.korean) ||
        !mapping.containsKey(ImportField.meaningZh)) {
      throw const FormatException('未找到“韩语单词”和“中文释义”两列，请检查表头。');
    }

    final drafts = <WordDraft>[];
    var invalidRows = 0;
    for (final row in rows.skip(1)) {
      final korean = _value(row, mapping[ImportField.korean]);
      final meaning = _value(row, mapping[ImportField.meaningZh]);
      if (korean.isEmpty && meaning.isEmpty) continue;
      if (korean.isEmpty || meaning.isEmpty) {
        invalidRows++;
        continue;
      }
      drafts.add(
        WordDraft(
          korean: korean,
          meaningZh: meaning,
          baseForm: _value(row, mapping[ImportField.baseForm]),
          pronunciation: _optional(row, mapping[ImportField.pronunciation]),
          partOfSpeech: _optional(row, mapping[ImportField.partOfSpeech]),
          exampleKo: _optional(row, mapping[ImportField.exampleKo]),
          exampleZh: _optional(row, mapping[ImportField.exampleZh]),
          topikLevel: _optional(row, mapping[ImportField.topikLevel]),
          category: _optional(row, mapping[ImportField.category]),
          tags: _optional(row, mapping[ImportField.tags]),
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
