import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../../services/fsrs_service.dart';
import '../../library/domain/providers.dart';
import '../../library/presentation/word_editor_sheet.dart';
import '../../library/presentation/word_detail_sheet.dart';
import '../domain/practice.dart';
import '../domain/providers.dart';
import 'study_controller.dart';
import 'study_content.dart';
import '../../../core/theme/app_motion.dart';
import 'session_sheet.dart';
import '../../ai/presentation/ai_assistant_sheet.dart';

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({super.key});
  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage>
    with WidgetsBindingObserver {
  final _answer = TextEditingController();
  int? _wordId;
  String? _sessionKey;
  bool? _correct;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _answer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(studyControllerProvider.notifier)
        .setAppActive(state == AppLifecycleState.resumed);
  }

  Future<void> _configure() async {
    final controller = ref.read(studyControllerProvider.notifier);
    controller.pauseForPanel();
    try {
      await showSessionSheet(context);
    } finally {
      if (mounted && controller.mounted) {
        controller.resumeFromPanel();
      }
    }
  }

  Future<void> _edit(Word word) async {
    final controller = ref.read(studyControllerProvider.notifier);
    controller.pauseForPanel();
    final saved = await showWordEditor(context, word: word);
    if (!mounted || !controller.mounted) return;
    controller.resumeFromPanel();
    if (saved == true) {
      ref.invalidate(libraryWordsProvider);
      await controller.load();
    }
  }

  Future<void> _explain(Word word) async {
    final controller = ref.read(studyControllerProvider.notifier);
    controller.pauseForPanel();
    try {
      await showAiAssistant(context, word, explain: true);
    } finally {
      if (mounted && controller.mounted) {
        controller.resumeFromPanel();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyControllerProvider);
    final controller = ref.read(studyControllerProvider.notifier);
    final options = ref.watch(sessionOptionsProvider);
    final colors = Theme.of(context).colorScheme;
    final reading =
        ref.watch(readingProvider).valueOrNull ?? const ReadingPreferences();
    final word = state.word;
    final forms = word != null && options.mode == PracticeMode.forms
        ? ref.watch(studyWordFormsProvider(word.id)).valueOrNull ?? ''
        : '';
    final favorite = word == null
        ? false
        : ref.watch(studyFavoriteProvider(word.id)).valueOrNull ?? false;
    if (_wordId != word?.id || _sessionKey != options.key) {
      _sessionKey = options.key;
      _wordId = word?.id;
      _answer.clear();
      _correct = null;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(options.daily ? '今日学习' : '本轮练习'),
        actions: [
          if (reading.focus)
            IconButton(
              tooltip: '返回首页',
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined),
            ),
          IconButton(
            tooltip: '撤销最近评分',
            onPressed: state.isSubmitting || state.isLoading
                ? null
                : () async {
                    _correct = null;
                    _answer.clear();
                    await controller.undo();
                  },
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: '练习设置',
            onPressed: _configure,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('读取失败：${state.error}'),
                    TextButton(
                      onPressed: controller.load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : word == null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    children: [
                      Icon(
                        Icons.task_alt_rounded,
                        size: 70,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '本轮完成，或暂时没有符合条件的词',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ref
                          .watch(dailyPlanProgressProvider)
                          .when(
                            data: (p) => Text(
                              '今天新词 ${p.newWordsDone} · 复习 ${p.reviewsDone} 次',
                            ),
                            loading: () => const SizedBox(),
                            error: (_, _) => const SizedBox(),
                          ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _configure,
                        child: const Text('继续新词 / 复习 / 混合练习'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(sessionOptionsProvider.notifier).daily();
                          controller.load();
                        },
                        child: const Text('返回每日基础计划'),
                      ),
                      TextButton(
                        onPressed: () => context.go('/library'),
                        child: const Text('去词库补充例句和词形'),
                      ),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Column(
                  children: [
                    options.daily
                        ? ref
                              .watch(studyRoundProgressProvider)
                              .when(
                                data: (p) =>
                                    _progress('每日新词', p.done, p.target),
                                loading: () => const SizedBox(),
                                error: (_, _) => const SizedBox(),
                              )
                        : ref
                              .watch(sessionProgressProvider)
                              .when(
                                data: (p) =>
                                    _progress('本轮练习', p.done, p.target),
                                loading: () => const SizedBox(),
                                error: (_, _) => const SizedBox(),
                              ),
                    Expanded(
                      child: Card(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          key: ValueKey('${word.id}:${options.key}'),
                          child: Builder(
                            builder: (context) {
                              final item = practiceItem(
                                word,
                                options,
                                forms: forms,
                                formIndex:
                                    ref
                                        .watch(sessionProgressProvider)
                                        .valueOrNull
                                        ?.done ??
                                    0,
                              );
                              final quiz = options.mode != PracticeMode.cards;
                              return Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: '收藏',
                                        onPressed: () async {
                                          final db = ref.read(databaseProvider);
                                          await db.setFavorite(
                                            word.id,
                                            !favorite,
                                          );
                                          ref.invalidate(
                                            studyFavoriteProvider(word.id),
                                          );
                                          ref.invalidate(libraryWordsProvider);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  favorite ? '已取消收藏' : '已收藏',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        icon: AnimatedSwitcher(
                                          duration: AppMotion.duration(
                                            context,
                                            160,
                                          ),
                                          transitionBuilder:
                                              (child, animation) =>
                                                  ScaleTransition(
                                                    scale: animation,
                                                    child: child,
                                                  ),
                                          child: Icon(
                                            favorite
                                                ? Icons.star_rounded
                                                : Icons.star_border_rounded,
                                            key: ValueKey(favorite),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: '编辑单词',
                                        onPressed: () => _edit(word),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: '单词详情',
                                        onPressed: () async {
                                          controller.pauseForPanel();
                                          try {
                                            await showWordDetail(context, word);
                                          } finally {
                                            if (mounted && controller.mounted) {
                                              controller.resumeFromPanel();
                                            }
                                          }
                                        },
                                        icon: const Icon(Icons.info_outline),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    item.question,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontSize: reading.wordSize,
                                          height: reading.lineHeight,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (word.partOfSpeech?.isNotEmpty == true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Chip(
                                        label: Text(word.partOfSpeech!),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  IconButton.filledTonal(
                                    tooltip: '播放发音',
                                    onPressed: () async {
                                      final rate =
                                          double.tryParse(
                                            await ref
                                                    .read(databaseProvider)
                                                    .loadSetting(
                                                      'speech_rate',
                                                    ) ??
                                                '',
                                          ) ??
                                          .45;
                                      await ref
                                          .read(ttsServiceProvider)
                                          .speakKorean(item.spoken, rate: rate);
                                    },
                                    icon: const Icon(Icons.volume_up_rounded),
                                  ),
                                  TextButton.icon(
                                    onPressed: state.isSubmitting
                                        ? null
                                        : () => _explain(word),
                                    icon: const Icon(Icons.auto_awesome),
                                    label: const Text('AI 解释'),
                                  ),
                                  if (quiz) ...[
                                    const SizedBox(height: 18),
                                    TextField(
                                      controller: _answer,
                                      enabled: _correct == null,
                                      decoration: const InputDecoration(
                                        labelText: '输入答案',
                                      ),
                                      onSubmitted: (_) {
                                        FocusScope.of(context).unfocus();
                                        setState(
                                          () => _correct = answerMatches(
                                            _answer.text,
                                            item.answer,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    if (_correct == null)
                                      OutlinedButton(
                                        onPressed: () {
                                          FocusScope.of(context).unfocus();
                                          setState(
                                            () => _correct = answerMatches(
                                              _answer.text,
                                              item.answer,
                                            ),
                                          );
                                        },
                                        child: const Text('检查答案'),
                                      )
                                    else ...[
                                      Text(
                                        _correct! ? '回答正确' : '需要再记一次',
                                        style: TextStyle(
                                          color: _correct!
                                              ? colors.primary
                                              : colors.error,
                                        ),
                                      ),
                                      Text(
                                        '参考答案：${item.answer}',
                                        textAlign: TextAlign.center,
                                      ),
                                      if (!_correct!)
                                        Wrap(
                                          children: [
                                            for (
                                              var i = 0;
                                              i < item.answer.length;
                                              i++
                                            )
                                              Text(
                                                item.answer[i],
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  color:
                                                      i < _answer.text.length &&
                                                          _answer.text[i] ==
                                                              item.answer[i]
                                                      ? colors.primary
                                                      : colors.error,
                                                ),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ] else if (state.isRevealed) ...[
                                    const SizedBox(height: 24),
                                    RevealContent(
                                      child: Column(
                                        children: [
                                          StudyMeaning(
                                            key: ValueKey(word.id),
                                            text: item.answer,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall
                                                ?.copyWith(
                                                  fontSize: reading.meaningSize,
                                                  height: reading.lineHeight,
                                                ),
                                          ),
                                          if (word.exampleKo?.isNotEmpty ==
                                                  true ||
                                              word.exampleZh?.isNotEmpty ==
                                                  true)
                                            ExpansionTile(
                                              title: const Text('例句与翻译'),
                                              initiallyExpanded: true,
                                              children: [
                                                if (word
                                                        .exampleKo
                                                        ?.isNotEmpty ==
                                                    true)
                                                  SelectableText(
                                                    word.exampleKo!,
                                                    textAlign: TextAlign.center,
                                                  ),
                                                if (word
                                                        .exampleZh
                                                        ?.isNotEmpty ==
                                                    true)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          vertical: 10,
                                                        ),
                                                    child: Text(
                                                      word.exampleZh!,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    StudyActions(
                      revealed: state.isRevealed,
                      busy: state.isSubmitting,
                      quiz: options.mode != PracticeMode.cards,
                      onReveal: controller.reveal,
                      onRate: (rating) {
                        FocusScope.of(context).unfocus();
                        controller.rate(rating);
                      },
                      onContinue: _correct == null
                          ? null
                          : () {
                              FocusScope.of(context).unfocus();
                              controller.reveal();
                              controller.rate(
                                _correct!
                                    ? StudyRating.good
                                    : StudyRating.again,
                              );
                            },
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _progress(String label, int done, int target) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      children: [
        Row(children: [Text(label), const Spacer(), Text('$done / $target')]),
        const SizedBox(height: 5),
        SmoothProgress(
          value: target <= 0 ? 0 : (done / target).clamp(0, 1).toDouble(),
        ),
      ],
    ),
  );
}
