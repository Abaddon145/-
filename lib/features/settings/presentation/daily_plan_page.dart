import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../services/fsrs_service.dart';
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
  double _retention = 0.9;
  bool _initialized = false;

  @override
  void dispose() {
    _newWords.dispose();
    _reviews.dispose();
    super.dispose();
  }

  String? _validateCount(String? value, int? maximum) {
    final count = int.tryParse(value ?? '');
    return count == null || count < 1 || (maximum != null && count > maximum)
        ? maximum == null
              ? '请输入大于 0 的整数'
              : '请输入 1–$maximum 之间的整数'
        : null;
  }

  late final Future<DailyPlanSettings> _settingsFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final database = ref.read(databaseProvider);
    _settingsFuture = database.loadDailyPlanSettings();
    database.loadSetting(retentionSettingKey).then((value) {
      if (!mounted) return;
      setState(() => _retention = normalizeDesiredRetention(value));
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final newWords = int.parse(_newWords.text);
    final reviews = int.parse(_reviews.text);

    setState(() => _saving = true);
    try {
      final database = ref.read(databaseProvider);
      await database.saveDailyPlanSettings(
        DailyPlanSettings(newWordsPerDay: newWords, reviewsPerDay: reviews),
      );
      await database.saveSetting(
        retentionSettingKey,
        _retention.toStringAsFixed(2),
      );
      ref.invalidate(dailyPlanSettingsProvider);
      ref.invalidate(dailyPlanProgressProvider);
      ref.invalidate(studyRoundProgressProvider);
      ref.invalidate(homeCountsProvider);
      ref.invalidate(studyControllerProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每日学习计划已保存')));
      context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) => _validateCount(value, null),
                        decoration: const InputDecoration(
                          labelText: '每日新词',
                          helperText: '数量不限，按自己的节奏设置',
                          prefixIcon: Icon(Icons.auto_stories_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _reviews,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) => _validateCount(value, 500),
                        decoration: const InputDecoration(
                          labelText: '每日复习上限',
                          helperText: '1–500 次。只限制已毕业的卡片',
                          prefixIcon: Icon(Icons.replay_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '记忆保留率',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final choice in retentionChoices)
                            ChoiceChip(
                              label: Text('${(choice * 100).round()}%'),
                              selected: _retention == choice,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() => _retention = choice),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '越高，到期越勤。默认 90%。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '学习时会先安排到期的复习，再加入今日新词。学习中和重学中的短步骤（例如 1 分钟、10 分钟）当天仍会出现，并且不计入复习上限。完成今日新词后，可以在学习页点击「再学一轮」继续。',
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
