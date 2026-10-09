import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/fsrs_service.dart';
import '../domain/providers.dart';
import 'study_controller.dart';

class StudyPage extends ConsumerWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyControllerProvider);
    final controller = ref.read(studyControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(ref.watch(studyBookProvider) == null ? '今日学习' : '词库专项学习'),
        actions: [
          if (ref.watch(studyBookProvider) != null)
            TextButton(onPressed: () => ref.read(studyBookProvider.notifier).state = null,
              child: const Text('返回日常')),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildBody(context, ref, state, controller),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    StudyUiState state,
    StudyController controller,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('学习数据读取失败：${state.error}'),
              const SizedBox(height: 16),
              FilledButton(onPressed: controller.load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final word = state.word;
    if (word == null) {
      return const _StudyCompletion();
    }
    return Padding(
      key: ValueKey(word.id),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          ref.watch(studyRoundProgressProvider).when(
            data: (round) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(children: [
                    Text(round.isExtra ? '加练新词' : '今日新词'),
                    const Spacer(),
                    Text('${round.done} / ${round.target}'),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: round.done / round.target),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Expanded(
            child: Card(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      word.korean,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    if (word.tags?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(word.tags!),
                    ],
                    if (word.baseForm.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('原形：${word.baseForm}'),
                    ],
                    const SizedBox(height: 12),
                    IconButton.filledTonal(
                      tooltip: '播放发音',
                      onPressed: () => ref
                          .read(ttsServiceProvider)
                          .speakKorean(word.korean),
                      icon: const Icon(Icons.volume_up_rounded),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: state.isRevealed
                          ? Padding(
                              padding: const EdgeInsets.only(top: 28),
                              child: Column(
                                children: [
                                  Text(
                                    word.meaningZh,
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  if (word.partOfSpeech != null) ...[
                                    const SizedBox(height: 8),
                                    Text(word.partOfSpeech!),
                                  ],
                                  if (word.exampleKo != null) ...[
                                    const SizedBox(height: 24),
                                    Text(word.exampleKo!,
                                        textAlign: TextAlign.center),
                                  ],
                                  if (word.exampleZh != null) ...[
                                    const SizedBox(height: 6),
                                    Text(word.exampleZh!,
                                        textAlign: TextAlign.center),
                                  ],
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!state.isRevealed)
            FilledButton(
              onPressed: controller.reveal,
              child: const Text('查看释义'),
            )
          else
            _RatingBar(
              disabled: state.isSubmitting,
              onRating: controller.rate,
            ),
        ],
      ),
    );
  }
}

class _StudyCompletion extends ConsumerWidget {
  const _StudyCompletion();

  Future<void> _continue(BuildContext context, WidgetRef ref, int defaultCount) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ExtraRoundSheet(defaultCount: defaultCount),
    );
    if (count == null || !context.mounted) return;
    await ref.read(studyControllerProvider.notifier).startExtraRound(count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(studyBookCountsProvider);
    final round = ref.watch(studyRoundProgressProvider).valueOrNull;
    final plan = ref.watch(dailyPlanProgressProvider).valueOrNull;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded, size: 72,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(
              counts.valueOrNull?.newWords == 0
                  ? '新词已全部学完'
                  : round?.isExtra == true ? '这一轮完成了' : '今天的计划已完成',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (plan != null)
              Text('今天已学 ${plan.newWordsDone} 个新词 · 复习 ${plan.reviewsDone} 次',
                  textAlign: TextAlign.center),
            const SizedBox(height: 24),
            counts.when(
              data: (value) => value.newWords > 0
                  ? Column(children: [
                      Text('词库还有 ${value.newWords} 个新词，可以继续下一轮。',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _continue(context, ref,
                            plan?.settings.newWordsPerDay ?? 20),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('再学一轮'),
                      ),
                    ])
                  : FilledButton.icon(
                      onPressed: () => context.go('/library'),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('去词库添加单词'),
                    ),
              loading: () => const CircularProgressIndicator(),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(studyBookCountsProvider),
                child: const Text('重新读取词库'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: () => context.go('/'), child: const Text('返回首页')),
          ],
        ),
      ),
    );
  }
}

class _ExtraRoundSheet extends StatefulWidget {
  const _ExtraRoundSheet({required this.defaultCount});
  final int defaultCount;
  @override
  State<_ExtraRoundSheet> createState() => _ExtraRoundSheetState();
}

class _ExtraRoundSheetState extends State<_ExtraRoundSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _count;
  @override
  void initState() {
    super.initState();
    _count = TextEditingController(text: '${widget.defaultCount}');
  }
  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('再学一轮', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('选择本轮新词数量，学习记录继续计入今天。'),
          const SizedBox(height: 20),
          TextFormField(
            controller: _count,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '本轮新词数量', helperText: '数量不限；词库不足时学完剩余新词即可'),
            validator: (value) {
              final count = int.tryParse(value ?? '');
              return count == null || count < 1 ? '请输入大于 0 的整数' : null;
            },
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final count in [10, 20, 50])
              ActionChip(label: Text('$count 个'), onPressed: () => _count.text = '$count'),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, int.parse(_count.text));
              }
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始下一轮'),
          ),
        ]),
      ),
    ),
  );
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.disabled, required this.onRating});

  final bool disabled;
  final ValueChanged<StudyRating> onRating;

  @override
  Widget build(BuildContext context) {
    const entries = [
      (StudyRating.again, '忘记'),
      (StudyRating.hard, '困难'),
      (StudyRating.good, '认识'),
      (StudyRating.easy, '简单'),
    ];
    return Row(
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              onPressed:
                  disabled ? null : () => onRating(entries[index].$1),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Text(entries[index].$2),
            ),
          ),
        ],
      ],
    );
  }
}
