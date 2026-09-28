import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

class DailyPlanPage extends ConsumerStatefulWidget {
  const DailyPlanPage({super.key});

  @override
  ConsumerState<DailyPlanPage> createState() => _DailyPlanPageState();
}

class _DailyPlanPageState extends ConsumerState<DailyPlanPage> {
  static const _newWordOptions = [5, 10, 15, 20, 30, 50, 100];
  static const _reviewOptions = [20, 50, 100, 150, 200, 300, 500];

  late final Future<DailyPlanSettings> _settingsFuture;
  int? _newWordsPerDay;
  int? _reviewsPerDay;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = ref.read(databaseProvider).loadDailyPlanSettings();
  }

  Future<void> _save() async {
    final newWords = _newWordsPerDay;
    final reviews = _reviewsPerDay;
    if (newWords == null || reviews == null || _saving) return;

    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).saveDailyPlanSettings(
            DailyPlanSettings(
              newWordsPerDay: newWords,
              reviewsPerDay: reviews,
            ),
          );
      ref.invalidate(dailyPlanSettingsProvider);
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(homeCountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每日学习计划已保存')),
      );
      context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('每日学习计划')),
      body: SafeArea(
        child: FutureBuilder<DailyPlanSettings>(
          future: _settingsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('读取设置失败：${snapshot.error}'),
                ),
              );
            }
            final settings = snapshot.data;
            if (settings == null) {
              return const Center(child: CircularProgressIndicator());
            }
            _newWordsPerDay ??= settings.newWordsPerDay;
            _reviewsPerDay ??= settings.reviewsPerDay;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '设置每天需要学习的新词数量，以及到期复习的最高次数。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<int>(
                  initialValue: _newWordsPerDay,
                  decoration: const InputDecoration(
                    labelText: '每日新词',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.auto_stories_rounded),
                  ),
                  items: [
                    for (final value in _newWordOptions)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value 个'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _newWordsPerDay = value),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  initialValue: _reviewsPerDay,
                  decoration: const InputDecoration(
                    labelText: '每日复习上限',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.replay_rounded),
                  ),
                  items: [
                    for (final value in _reviewOptions)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value 次'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _reviewsPerDay = value),
                ),
                const SizedBox(height: 16),
                const Text(
                  '学习时会优先安排已经到期的复习词，然后加入今日新词。当天达到设置数量后，应用会显示“今日学习计划已完成”。',
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('保存计划'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
