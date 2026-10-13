import 'dart:convert';
import '../../../core/database/app_database.dart';

class LearningReport {
  static Future<String> csv(AppDatabase db,DateTime now)async {
    final rows=await db.loadRecentStatistics(now,days:30);
    final result=<String>['日期,新词数量,复习次数,认识次数,忘记次数,有效学习秒数'];
    for(final row in rows){ result.add('${dayKey(row.date)},${row.newWords},${row.reviews},${row.correct},${row.wrong},${row.durationMs~/1000}'); }
    return '\uFEFF${result.join('\n')}';
  }
  static Future<String> weekly(AppDatabase db,DateTime now)async {
    final rows=await db.loadRecentStatistics(now),checkins=await db.loadCheckins(now);
    final wrong=await db.searchLibraryWords(query:'',filter:LibraryFilter.wrong);
    var total=0,correct=0;
    for(final row in rows){final raw=await db.loadSetting('objective:${dayKey(row.date)}');if(raw!=null){final data=jsonDecode(raw) as Map;total+=data['total'] as int;correct+=data['correct'] as int;}}
    final forecast=await db.reviewForecast(now);
    return '# 学习周报 · ${dayKey(now)}\n\n'
      '新词 ${rows.fold<int>(0,(n,r)=>n+r.newWords)} · 复习 ${rows.fold<int>(0,(n,r)=>n+r.reviews)} 次\n'
      '有效学习 ${rows.fold<int>(0,(n,r)=>n+r.durationMs)~/60000} 分钟\n'
      '连续打卡 ${checkins.streak} 天 · 累计 ${checkins.days.length} 天\n'
      '客观测试 ${total==0?'暂无记录':'$correct/$total'}\n\n'
      '## 待强化词\n${wrong.take(100).map((e)=>'- ${e.word.korean} — ${e.word.meaningZh}').join('\n')}\n\n'
      '## 未来七天复习\n${forecast.map((d)=>'- ${d['day']}：${d['count']} 个').join('\n')}\n';
  }
}
