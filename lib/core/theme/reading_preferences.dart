import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/study/domain/providers.dart';

class ReadingPreferences {
  const ReadingPreferences({this.wordSize=32,this.meaningSize=24,this.lineHeight=1.4,this.focus=false});
  final double wordSize;
  final double meaningSize;
  final double lineHeight;
  final bool focus;
}
final readingProvider=FutureProvider<ReadingPreferences>((ref)async {
  final db=ref.watch(databaseProvider);
  return ReadingPreferences(wordSize:double.tryParse(await db.loadSetting('word_size')??'')??32,
    meaningSize:double.tryParse(await db.loadSetting('meaning_size')??'')??24,
    lineHeight:double.tryParse(await db.loadSetting('line_height')??'')??1.4,
    focus:await db.loadSetting('focus_mode')=='true');
});
