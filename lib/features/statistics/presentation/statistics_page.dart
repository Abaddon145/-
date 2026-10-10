import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/providers.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats=ref.watch(recentStatisticsProvider);
    return Scaffold(appBar:AppBar(title:const Text('学习统计'), actions:[
      IconButton(tooltip:'刷新统计', onPressed:()=>ref.invalidate(recentStatisticsProvider), icon:const Icon(Icons.refresh_rounded)),
    ]),body:stats.when(
      loading:()=>const Center(child:CircularProgressIndicator()),
      error:(e,_)=>Center(child:Text('读取统计失败：$e')),
      data:(days){
        final today=days.isEmpty?null:days.last;
        final total=days.fold<int>(0,(sum,d)=>sum+d.newWords+d.reviews);
        final correct=days.fold<int>(0,(sum,d)=>sum+d.correct);
        final wrong=days.fold<int>(0,(sum,d)=>sum+d.wrong);
        final accuracy=correct+wrong==0?0:(correct*100/(correct+wrong)).round();
        final mins=days.fold<int>(0,(sum,d)=>sum+d.durationMs)~/60000;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(recentStatisticsProvider);
            await ref.read(recentStatisticsProvider.future);
          },
          child: ListView(physics:const AlwaysScrollableScrollPhysics(), padding:const EdgeInsets.all(16),children:[
          Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('今日',style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:12),
            Text('新词  ${today?.newWords??0}'),
            Text('复习  ${today?.reviews??0}'),
            Text('正确率  ${today == null || today.correct + today.wrong == 0 ? 0 : (today.correct * 100 / (today.correct + today.wrong)).round()}%'),
            Text('学习时长  ${(today?.durationMs ?? 0) ~/ 60000} 分钟'),
          ]))),
          Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text('近 7 天 · $total 次 · 正确率 $accuracy% · $mins 分钟',style:Theme.of(context).textTheme.titleMedium)),
          for(final day in days) ListTile(
            contentPadding:EdgeInsets.zero,
            title:Text('${day.date.month}月${day.date.day}日'),
            subtitle:Text('新词 ${day.newWords} · 复习 ${day.reviews}'),
            trailing:Text('${day.correct} 对 / ${day.wrong} 错'),
          ),
        ]));
      }));
  }
}
