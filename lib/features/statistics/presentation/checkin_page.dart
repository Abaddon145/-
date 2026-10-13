import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

class CheckinPage extends ConsumerStatefulWidget {
  const CheckinPage({super.key});
  @override ConsumerState<CheckinPage> createState() => _CheckinPageState();
}
class _CheckinPageState extends ConsumerState<CheckinPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Future<void> _check() async {
    try {
      await ref.read(databaseProvider).checkIn(DateTime.now()); ref.invalidate(checkinsProvider);
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
  }
  @override Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = ref.watch(checkinsProvider);
    final offset = _month.weekday - 1;
    final count = DateTime(_month.year,_month.month+1,0).day;
    return Scaffold(appBar: AppBar(title: const Text('学习打卡')), body: summary.when(
      loading: () => const Center(child: CircularProgressIndicator()), error: (e,_) => Center(child: Text('$e')),
      data: (value) => ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          Text('连续 ${value.streak} 天', style: Theme.of(context).textTheme.headlineMedium),
          Text('累计 ${value.days.length} 天 · 最长 ${value.longest} 天'), const SizedBox(height: 14),
          FilledButton(onPressed: value.days.contains(dayKey(DateTime.now())) ? null : _check,
            child: Text(value.days.contains(dayKey(DateTime.now())) ? '今天已打卡 ✓' : '今日打卡')),
          const SizedBox(height: 8), const Text('完成一次学习即可打卡；默认自动打卡。')]))),
        const SizedBox(height: 18),
        Row(children: [IconButton(onPressed: () => setState(() => _month = DateTime(_month.year,_month.month-1)), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${_month.year} 年 ${_month.month} 月', textAlign: TextAlign.center)),
          IconButton(onPressed: () => setState(() => _month = DateTime(_month.year,_month.month+1)), icon: const Icon(Icons.chevron_right))]),
        GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), children: [
          for (final label in const ['一','二','三','四','五','六','日']) Center(child: Text(label)),
          for (var i=0;i<offset;i++) const SizedBox(),
          for (var d=1;d<=count;d++) Padding(padding: const EdgeInsets.all(4), child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: value.days.contains(dayKey(DateTime(_month.year,_month.month,d))) ? colors.primaryContainer : colors.surfaceContainerLow),
            child: Center(child: Text('$d')))),
        ]),
        const SizedBox(height: 18),
        Text('学习里程碑', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 8, children: [for (final milestone in const [7,30,100]) Chip(
          avatar: Icon(value.days.length>=milestone ? Icons.verified_rounded : Icons.lock_outline, size: 18), label: Text('$milestone 天'))]),
        FutureBuilder<String?>(future: ref.read(databaseProvider).loadSetting('auto_checkin'), builder: (context,s) => SwitchListTile(
          title: const Text('学习后自动打卡'), value: s.data != 'false', onChanged: (v) async {
            await ref.read(databaseProvider).saveSetting('auto_checkin', '$v'); if (mounted) setState(() {});
          })),
      ])));
  }
}
