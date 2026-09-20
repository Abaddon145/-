import '../../../core/database/app_database.dart';

enum ImportField {
  korean('韩语单词'),
  meaningZh('中文释义'),
  baseForm('原形'),
  pronunciation('发音'),
  partOfSpeech('词性'),
  exampleKo('韩语例句'),
  exampleZh('中文例句'),
  topikLevel('TOPIK 等级'),
  category('分类'),
  tags('标签'),
  note('备注'),
  hanja('汉字词'),
  etymology('词源');

  const ImportField(this.label);
  final String label;
}

class ParsedWorkbook {
  const ParsedWorkbook({
    required this.sheetName,
    required this.headers,
    required this.mapping,
    required this.drafts,
    required this.invalidRows,
  });

  final String sheetName;
  final List<String> headers;
  final Map<ImportField, int> mapping;
  final List<WordDraft> drafts;
  final int invalidRows;
}
