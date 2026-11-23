import '../../../core/database/app_database.dart';

String mnemonicCacheKey(Word word) => 'mnemonic:${word.language}:${word.id}';

String mnemonicPrompt(Word word) {
  if (word.language == 'en') {
    return '用中文给英语学习者拆解「${word.headword}」（${word.meaningZh}）。'
        '说明词根或前后缀，并给一个简短英文例句和中文翻译。不要写韩文。只输出一段纯文本。';
  }
  return '用中文给韩语学习者说明「${word.headword}」（${word.meaningZh}）。'
      '写必要的语法或活用提示，并给一个简短韩文例句和中文翻译。只输出一段纯文本。';
}
