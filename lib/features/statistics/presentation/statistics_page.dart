import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../domain/providers.dart';
import '../data/learning_report.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});
  Future<void> _export(BuildContext context,WidgetRef ref,bool csv)async {
    try {
      final db=ref.read(databaseProvider);
      final text=csv?await LearningReport.csv(db,DateTime.now()):await LearningReport.weekly(db,DateTime.now());
      await FilePicker.saveFile(fileName:csv?'learning-report.csv':'learning-weekly.md',
        bytes:Uint8List.fromList(utf8.encode(text)),mimeType:csv?'text/csv':'text/markdown');
    } catch(e){if(context.mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('导出失败：$e')));}}
  }
  @override Widget build(BuildContext context,WidgetRef ref) {
    final stats=ref.watch(recentStatisticsProvider), colors=Theme.of(context).colorScheme;
    final objective=ref.watch(objectiveStatisticsProvider).valueOrNull??{};
    return Scaffold(appBar:AppBar(title:const Text('学习统计'),actions:[
      IconButton(tooltip:'刷新统计',onPressed:(){ref.invalidate(recentStatisticsProvider);ref.invalidate(monthStatisticsProvider);ref.invalidate(learningOverviewProvider);ref.invalidate(reviewForecastProvider);},icon:const Icon(Icons.refresh_rounded)),
      PopupMenuButton<String>(tooltip:'导出学习报告',onSelected:(v)=>_export(context,ref,v=='csv'),itemBuilder:(_)=>const[PopupMenuItem(value:'csv',child:Text('导出30天 CSV')),PopupMenuItem(value:'weekly',child:Text('导出本周报告'))]),
    ]),body:stats.when(loading:()=>const Center(child:CircularProgressIndicator()),error:(e,_)=>Center(child:Text('读取统计失败：$e')),data:(days){
      final today=days.isEmpty?null:days.last;
      final total=days.fold<int>(0,(n,r)=>n+r.newWords+r.reviews);
      final correct=days.fold<int>(0,(n,r)=>n+r.correct),wrong=days.fold<int>(0,(n,r)=>n+r.wrong);
      final mins=days.fold<int>(0,(n,r)=>n+r.durationMs)~/60000;
      final testTotal=days.fold<int>(0,(n,r)=>n+(objective[dayKey(r.date)]?['total']??0));
      final testCorrect=days.fold<int>(0,(n,r)=>n+(objective[dayKey(r.date)]?['correct']??0));
      final selfTotal=correct+wrong-testTotal,selfCorrect=correct-testCorrect;
      final accuracy=selfTotal<=0?0:(selfCorrect*100/selfTotal).round();
      final todayTest=objective[today==null?'':dayKey(today.date)]??{'total':0,'correct':0};
      final todaySelfTotal=(today?.correct??0)+(today?.wrong??0)-todayTest['total']!;
      final todayAccuracy=todaySelfTotal<=0?0:(((today?.correct??0)-todayTest['correct']!)*100/todaySelfTotal).round();
      return RefreshIndicator(onRefresh:()async{ref.invalidate(recentStatisticsProvider);await ref.read(recentStatisticsProvider.future);},child:ListView(
        physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(18),children:[
          Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('今日',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),
            Text('新词  ${today?.newWords??0}'),Text('复习  ${today?.reviews??0}'),
            Text('自评记忆率  $todayAccuracy%'),Text('学习时长  ${(today?.durationMs??0)~/60000} 分钟'),
            Text('客观测试  ${todayTest['correct']}/${todayTest['total']}'),
          ]))),
          ref.watch(learningOverviewProvider).when(data:(v)=>Card(child:Padding(padding:const EdgeInsets.all(18),child:Text('已学不同单词 ${v['learned']} · 已标熟词 ${v['known']} · 暂停 ${v['suspended']}'))),loading:()=>const SizedBox(),error:(_,_)=>const SizedBox()),
          Card(child:ListTile(leading:const Icon(Icons.calendar_month_rounded),title:ref.watch(checkinsProvider).when(data:(v)=>Text('连续打卡 ${v.streak} 天 · 最长 ${v.longest} 天'),loading:()=>const Text('学习日历'),error:(_,_)=>const Text('学习日历')),trailing:const Icon(Icons.chevron_right),onTap:()=>context.push('/checkin'))),
          Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text('近 7 天 · $total 次 · 自评记忆率 $accuracy% · $mins 分钟',style:Theme.of(context).textTheme.titleMedium)),
          Text('客观测试：$testCorrect / $testTotal'),
          for(final day in days)ListTile(contentPadding:EdgeInsets.zero,title:Text('${day.date.month}月${day.date.day}日'),subtitle:Text('新词 ${day.newWords} · 复习 ${day.reviews}'),trailing:Text('${day.correct} 认识 / ${day.wrong} 忘记')),
          const Divider(),Text('近30天学习热力图',style:Theme.of(context).textTheme.titleMedium),
          ref.watch(monthStatisticsProvider).when(data:(rows)=>Wrap(spacing:4,runSpacing:4,children:[for(final row in rows)Tooltip(message:'${dayKey(row.date)} · ${row.newWords+row.reviews} 次',child:Container(width:32,height:32,decoration:BoxDecoration(borderRadius:BorderRadius.circular(6),color:row.newWords+row.reviews==0?colors.surfaceContainerHighest:colors.primary.withValues(alpha:(.2+.8*((row.newWords+row.reviews)/50).clamp(0,1)))),child:Center(child:Text('${row.date.day}',style:const TextStyle(fontSize:11)))))]),loading:()=>const LinearProgressIndicator(),error:(_,_)=>const SizedBox()),
          const SizedBox(height:18),Text('未来7天到期复习',style:Theme.of(context).textTheme.titleMedium),
          ref.watch(reviewForecastProvider).when(data:(rows)=>Column(children:[for(final row in rows)ListTile(contentPadding:EdgeInsets.zero,title:Text('${row['day']}'),trailing:Text('${row['count']} 个'))]),loading:()=>const LinearProgressIndicator(),error:(_,_)=>const SizedBox()),
        ]));
    }));
  }
}
