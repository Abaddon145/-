import 'dart:typed_data';

import 'xlsx_text_reader.dart';

import '../../../core/database/app_database.dart';
import '../domain/import_models.dart';

class ExcelImportService {
  static const _aliases = <ImportField, Set<String>>{
    ImportField.korean: {'韩语单词', '韩语', '单词', '단어', 'word', 'korean', '英语 / 韩语', '英文 / 韩文', '英语/韩文', '英韩', '한국어'},
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

  Uint8List? _cachedBytes;
  Map<String, List<List<String>>>? _cachedSheets;
  Map<String, List<List<String>>> _sheets(Uint8List bytes) {
    if (!identical(bytes, _cachedBytes)) {
      final decoded = XlsxTextReader().read(bytes);
      _cachedBytes = bytes;
      _cachedSheets = decoded;
    }
    return _cachedSheets!;
  }
  int _headerIndex(List<List<String>> rows) {
    for (var i = 0; i < rows.length && i < 20; i++) {
      final mapping = guessMapping(rows[i]);
      if (mapping.containsKey(ImportField.korean) || mapping.containsKey(ImportField.english)) return i;
    }
    return 0;
  }
  List<String> sheetNames(Uint8List bytes) => _sheets(bytes).keys.toList();
  List<String> sheetHeaders(Uint8List bytes, String name) {
    final rows = _sheets(bytes)[name];
    if (rows == null) throw const FormatException('工作表不存在，请重新选择');
    return rows[_headerIndex(rows)];
  }
  ParsedWorkbook parseFirstSheet(Uint8List bytes, {String? sheetName, Map<ImportField,int>? mappingOverride, bool allSheets=false}) {
    final sheets = _sheets(bytes);
    if (allSheets) {
      final drafts = <WordDraft>[];
      var invalid = 0;
      for (final name in sheets.keys) {
        try {
          final parsed = parseFirstSheet(bytes, sheetName: name);
          drafts.addAll(parsed.drafts); invalid += parsed.invalidRows;
        } on FormatException { invalid += sheets[name]!.length; }
      }
      return ParsedWorkbook(sheetName:'全部工作表',headers:const [],mapping:const {},drafts:drafts,invalidRows:invalid);
    }
    final name = sheetName ?? sheets.keys.first;
    final rows = sheets[name];
    if (rows == null) throw const FormatException('工作表不存在，请重新选择');
    final headerIndex = _headerIndex(rows);
    final headers = rows[headerIndex];
    final mapping = mappingOverride ?? guessMapping(headers);
    if (!mapping.containsKey(ImportField.korean) && !mapping.containsKey(ImportField.english)) {
      throw const FormatException('未识别单词列，请在下方手动选择韩语或英文列');
    }
    return ParsedWorkbook(sheetName:name,headers:headers,mapping:mapping,drafts:drafts,invalidRows:invalidRows);
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

  String _cellText(String cell) => cell.trim();

  String _value(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return _cellText(row[index]);
  }

  String? _optional(List<String> row, int? index) {
    final value = _value(row, index);
    return value.isEmpty ? null : value;
  }

  String _normalizeHeader(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-/／（）()]'), '')
        .trim();
  }
}
