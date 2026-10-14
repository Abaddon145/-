import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

class CheckinPage extends ConsumerStatefulWidget {
  const CheckinPage({super.key});
  @override
  ConsumerState<CheckinPage> createState() => _CheckinPageState();
}
class _CheckinPageState extends ConsumerState<CheckinPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<String?> _autoCheckin;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _autoCheckin = ref.read(databaseProvider).loadSetting('auto_checkin');
  }
  Future<void> _check() async {
    try {
      await ref.read(databaseProvider).checkIn(DateTime.now());
      ref.invalidate(checkinsProvider);
    } catch (error) { _showError(error); }
  }
  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
  Future<void> _setAuto(bool value) async {
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).saveSetting('auto_checkin', '$value');
      if (mounted) { setState(() => _autoCheckin = Future.value('$value')); }
    } catch (error) { _showError(error); }
    finally { if (mounted) { setState(() => _saving = false); } }
  }
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = ref.watch(checkinsProvider);
    final offset = _month.weekday - 1;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    return Scaffold(appBar: AppBar(title: const Text('学习打卡')),
      body: SafeArea(top: false, child: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (value) {
          final checked = value.days.toSet();
          final todayChecked = checked.contains(dayKey(DateTime.now()));
          return CustomScrollView(slivers: [
            SliverPadding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(child: Card(child: Padding(
                padding: const EdgeInsets.all(22), child: Column(children: [
                  Text('连续 ${value.streak} 天', style: Theme.of(context).textTheme.headlineMedium),
                  Text('累计 ${value.days.length} 天 · 最长 ${value.longest} 天'),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: todayChecked ? null : _check,
                    child: Text(todayChecked ? '今天已打卡 ✓' : '今日打卡')),
                  const SizedBox(height: 8),
                  const Text('完成一次学习即可打卡；默认自动打卡。', textAlign: TextAlign.center),
                ]),
              )))),
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverToBoxAdapter(child: Row(children: [
                IconButton(tooltip: '上个月', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
                Expanded(child: Text('${_month.year} 年 ${_month.month} 月', textAlign: TextAlign.center)),
                IconButton(tooltip: '下个月', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
              ]))),
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
                itemCount: 7 + offset + count,
                itemBuilder: (context, index) {
                  if (index < 7) {
                    return Center(child: Text(const ['一','二','三','四','五','六','日'][index]));
                  }
                  final day = index - 7 - offset + 1;
                  if (day < 1) { return const SizedBox.shrink(); }
                  final marked = checked.contains(dayKey(DateTime(_month.year, _month.month, day)));
                  return Padding(padding: const EdgeInsets.all(4), child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: marked ? colors.primaryContainer : colors.surfaceContainerLow),
                    child: Center(child: Text('$day')),
                  ));
                },
              )),
            SliverPadding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('学习里程碑', style: Theme.of(context).textTheme.titleMedium),
                Wrap(spacing: 8, children: [for (final milestone in const [7,30,100]) Chip(
                  avatar: Icon(value.days.length >= milestone ? Icons.verified_rounded : Icons.lock_outline, size: 18),
                  label: Text('$milestone 天'))]),
                FutureBuilder<String?>(future: _autoCheckin, builder: (context, snapshot) => SwitchListTile(
                  title: const Text('学习后自动打卡'), value: snapshot.data != 'false',
                  onChanged: _saving || snapshot.connectionState != ConnectionState.done ? null : _setAuto,
                )),
              ]))),
          ]);
        },
      )),
    );
  }
}
