import 'package:flutter/material.dart';
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
      appBar: AppBar(title: const Text('今日学习')),
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 72),
              SizedBox(height: 16),
              Text('当前词库已完成', style: TextStyle(fontSize: 22)),
              SizedBox(height: 8),
              Text('可以返回首页导入新的 Excel 词库。'),
            ],
          ),
        ),
      );
    }
    return Padding(
      key: ValueKey(word.id),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      word.korean,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    if (word.baseForm.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('原形：${word.baseForm}'),
                    ],
                    const SizedBox(height: 12),
                    IconButton.filledTonal(
                      tooltip: '播放韩语发音',
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
