import '../../../core/database/app_database.dart';

class CsvImportResult {
  const CsvImportResult({required this.drafts, required this.invalidRows});
  final List<WordDraft> drafts;
  final int invalidRows;
}

class CsvImportService {
  CsvImportResult parse(String text) {
    final rows = _rows(text);
    if (rows.isEmpty) {
      throw const FormatException('文件是空的');
    }
    final header = rows.first.map((cell) => cell.trim().toLowerCase()).toList();
    final columns = _columns(header);
    if (columns.headword == null || columns.meaning == null) {
      throw const FormatException('需要表头：词头、中文。可选 IPA、词性、例句、例句中文');
    }
    final drafts = <WordDraft>[];
    var invalid = 0;
    for (final row in rows.skip(1)) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final headword = _cell(row, columns.headword);
      final meaning = _cell(row, columns.meaning);
      if (headword.isEmpty || meaning.isEmpty) {
        invalid++;
        continue;
      }
      final example = _cell(row, columns.example);
      final exampleZh = _cell(row, columns.exampleZh);
      drafts.add(
        WordDraft(
          korean: headword,
          meaningZh: meaning,
          ipa: _optional(row, columns.ipa),
          partOfSpeech: _optional(row, columns.pos),
          exampleKo: example.isEmpty ? null : example,
          exampleZh: exampleZh.isEmpty ? null : exampleZh,
        ),
      );
    }
    return CsvImportResult(drafts: drafts, invalidRows: invalid);
  }

  String _cell(List<String> row, int? index) =>
      index == null || index >= row.length ? '' : row[index].trim();

  String? _optional(List<String> row, int? index) {
    final value = _cell(row, index);
    return value.isEmpty ? null : value;
  }
}

class _CsvColumns {
  const _CsvColumns({
    this.headword,
    this.meaning,
    this.ipa,
    this.pos,
    this.example,
    this.exampleZh,
  });
  final int? headword, meaning, ipa, pos, example, exampleZh;
}

_CsvColumns _columns(List<String> header) {
  int? find(Set<String> names) {
    for (var i = 0; i < header.length; i++) {
      if (names.contains(header[i])) return i;
    }
    return null;
  }

  final example = find({'例句', 'example', '英文例句', '英语例句'});
  return _CsvColumns(
    headword: find({'词头', '单词', '英文', '英文单词', 'word', 'english', 'headword'}),
    meaning: find({'中文', '释义', '中文释义', 'meaning', 'meaning_zh'}),
    ipa: find({'ipa', '音标'}),
    pos: find({'词性', 'pos', 'part_of_speech'}),
    example: example,
    exampleZh: find({'例句中文', '中文例句', 'example_zh', '翻译'}),
  );
}

List<List<String>> _rows(String text) {
  final source = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (source.isEmpty) return const [];
  final firstLine = source.split('\n').first;
  final delimiter =
      '\t'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? '\t'
      : ',';
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
    } else if (char == delimiter) {
      row.add(cell.toString());
      cell.clear();
    } else if (char == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(List.of(row));
      row.clear();
    } else {
      cell.write(char);
    }
  }
  row.add(cell.toString());
  if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
  return rows;
}
