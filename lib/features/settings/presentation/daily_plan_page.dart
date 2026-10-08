import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';

class DailyPlanPage extends ConsumerStatefulWidget {
  const DailyPlanPage({super.key});

  @override
  ConsumerState<DailyPlanPage> createState() => _DailyPlanPageState();
}

class _DailyPlanPageState extends ConsumerState<DailyPlanPage> {
  final _form = GlobalKey<FormState>();
  final _newWords = TextEditingController();
  final _reviews = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _newWords.dispose();
    _reviews.dispose();
    super.dispose();
  }

  String? _validateCount(String? value, int maximum) {
    final count = int.tryParse(value ?? '');
    return count == null || count < 1 || count > maximum
        ? '请输入 1–$maximum 之间的整数'
        : null;
  }

  late final Future<DailyPlanSettings> _settingsFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = ref.read(databaseProvider).loadDailyPlanSettings();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final newWords = int.parse(_newWords.text);
    final reviews = int.parse(_reviews.text);

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
      ref.invalidate(studyControllerProvider);
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
            if (!_initialized) {
              _newWords.text = '${settings.newWordsPerDay}';
              _reviews.text = '${settings.reviewsPerDay}';
              _initialized = true;
            }

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '设置每天需要学习的新词数量，以及到期复习的最高次数。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Form(
                  key: _form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newWords,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) => _validateCount(value, 100),
                        decoration: const InputDecoration(
                          labelText: '每日新词',
                          helperText: '1–100 个，按自己的节奏设置',
                          prefixIcon: Icon(Icons.auto_stories_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _reviews,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) => _validateCount(value, 500),
                        decoration: const InputDecoration(
                          labelText: '每日复习上限',
                          helperText: '1–500 次，只安排已到期的内容',
                          prefixIcon: Icon(Icons.replay_rounded),
                        ),
                      ),
                    ],
                  ),
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
