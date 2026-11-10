import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../library/domain/providers.dart';
import '../../library/presentation/word_editor_sheet.dart';
import '../../library/presentation/word_detail_sheet.dart';
import '../domain/empty_queue.dart';
import '../domain/practice.dart';
import '../domain/providers.dart';
import '../domain/study_draft.dart';
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
  final _answerFocus = FocusNode();
  late final StateController<bool> _typing;
  int? _wordId;
  String? _sessionKey;
  bool? _correct;
  @override
  void initState() {
    super.initState();
    _typing = ref.read(studyTypingProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _answerFocus.addListener(_onAnswerFocus);
  }

  void _onAnswerFocus() {
    final typing = _answerFocus.hasFocus;
    if (_typing.state != typing) _typing.state = typing;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _answerFocus.removeListener(_onAnswerFocus);
    _typing.state = false;
    _answerFocus.dispose();
    _answer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    ref.read(studyControllerProvider.notifier).setAppActive(active);
    if (!active) _saveDraft();
  }

  Future<void> _saveDraft() async {
    final current = ref.read(studyControllerProvider);
    final word = current.word;
    if (word == null) return;
    final options = ref.read(sessionOptionsProvider);
    final draft = StudyDraft(
      wordId: word.id,
      sessionKey: options.key,
      answer: _answer.text,
      revealed: current.isRevealed || _correct != null,
      correct: _correct,
    );
    try {
      await ref.read(databaseProvider).saveSetting(StudyDraft.storageKey, draft.encode());
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      await ref.read(databaseProvider).saveSetting(StudyDraft.storageKey, null);
    } catch (_) {}
  }

  Future<void> _restoreDraft(int wordId, String sessionKey) async {
    final raw = await ref.read(databaseProvider).loadSetting(StudyDraft.storageKey);
    if (!mounted || _wordId != wordId || _answer.text.isNotEmpty) return;
    final draft = StudyDraft.decode(raw);
    if (draft == null || draft.wordId != wordId || draft.sessionKey != sessionKey) return;
    _answer.text = draft.answer;
    _answer.selection = TextSelection.collapsed(offset: _answer.text.length);
    setState(() => _correct = draft.correct);
    if (draft.revealed || draft.correct != null) {
      ref.read(studyControllerProvider.notifier).reveal();
    }
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
      final nextId = word?.id;
      final nextKey = options.key;
      _sessionKey = nextKey;
      _wordId = nextId;
      _answer.clear();
      _correct = null;
      if (nextId != null) {
        final quiz = options.mode != PracticeMode.cards;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _wordId != nextId) return;
          if (quiz && _correct == null) _answerFocus.requestFocus();
        });
        _restoreDraft(nextId, nextKey);
      }
    }
    ref.listen(studyControllerProvider, (previous, next) {
      final notice = next.notice;
      if (notice == null || notice == previous?.notice) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    });
    ref.listen(studyVisibleProvider, (previous, next) {
      if (next == false) _answerFocus.unfocus();
    });
    final quiz = options.mode != PracticeMode.cards;
    final practice = word == null
        ? null
        : practiceItem(
            word,
            options,
            forms: forms,
            formIndex: ref.watch(sessionProgressProvider).valueOrNull?.done ?? 0,
          );
    Future<void> grade() async {
      final current = practice;
      if (current == null) return;
      FocusScope.of(context).unfocus();
      setState(() => _correct = answerMatches(_answer.text, current.answer));
      controller.reveal();
    }

    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
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
            tooltip: state.canUndo ? '撤销最近评分' : '没有可以撤销的评分',
            onPressed: state.canUndo && !state.isSubmitting && !state.isLoading
                ? () async {
                    final message = await controller.undo();
                    if (!context.mounted || message.isEmpty) return;
                    if (message.startsWith('已撤销')) {
                      _correct = null;
                      _answer.clear();
                      if (!AppMotion.reduced(context)) {
                        HapticFeedback.lightImpact().ignore();
                      }
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                : null,
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
                    Text(
                      state.error is FormatException
                          ? '读取失败：${(state.error! as FormatException).message}'
                          : '读取失败，请重试',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: controller.load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : word == null
            ? _EmptyStudy(
                options: options,
                kind: ref.watch(emptyQueueReasonProvider).valueOrNull,
                today: ref.watch(dailyPlanProgressProvider).when(
                  data: (p) => '今天新词 ${p.newWordsDone} · 复习 ${p.reviewsDone} 次',
                  loading: () => '',
                  error: (_, _) => '',
                ),
                onExtra: state.isLoading
                    ? null
                    : () async {
                        final count =
                            ref.read(dailyPlanProgressProvider).valueOrNull?.settings.newWordsPerDay ??
                            DailyPlanSettings.defaultNewWords;
                        await controller.startExtraRound(count);
                      },
                onConfigure: _configure,
                onDaily: () {
                  ref.read(sessionOptionsProvider.notifier).daily();
                  controller.load();
                },
                onLibrary: () => context.go('/library'),
              )
            : Padding(
                padding: EdgeInsets.fromLTRB(18, 8, 18, 16 + keyboard),
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
                              final item = practice!;
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
                                  if (!quiz && state.isRevealed) ...[
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
                    if (quiz && practice != null) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _answer,
                        focusNode: _answerFocus,
                        enabled: _correct == null,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        enableSuggestions: false,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: const InputDecoration(labelText: '输入答案'),
                        onSubmitted: (_) => grade(),
                      ),
                      const SizedBox(height: 8),
                      if (_correct == null)
                        OutlinedButton(
                          onPressed: grade,
                          child: const Text('检查答案'),
                        )
                      else ...[
                        Text(
                          _correct! ? '回答正确' : '需要再记一次',
                          style: TextStyle(
                            color: _correct! ? colors.primary : colors.error,
                          ),
                        ),
                        Text('参考答案：${practice.answer}', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(
                          _correct!
                              ? '建议记为「认识」。记得很吃力可选「困难」，毫不费力可选「简单」。'
                              : '如果只是差一点，可选「困难」，不必把整张卡片记成忘记。',
                          textAlign: TextAlign.center,
                        ),
                        if (!_correct!) _AnswerDiffView(input: _answer.text, expected: practice.answer),
                      ],
                    ],
                    const SizedBox(height: 12),
                    StudyActions(
                      revealed: quiz ? _correct != null : state.isRevealed,
                      busy: state.isSubmitting,
                      hold: quiz && _correct == null,
                      intervals: state.intervals,
                      onReveal: controller.reveal,
                      onRate: (rating) {
                        FocusScope.of(context).unfocus();
                        if (quiz && !state.isRevealed) controller.reveal();
                        _clearDraft();
                        controller.rate(rating);
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _progress(String label, int done, int target) {
    final value = target <= 0 ? 0.0 : (done / target).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label: '$label，已完成 $done，目标 $target',
        value: '${(value * 100).round()}%',
        child: Column(
          children: [
            Row(children: [Text(label), const Spacer(), Text('$done / $target')]),
            const SizedBox(height: 5),
            ExcludeSemantics(child: SmoothProgress(value: value)),
          ],
        ),
      ),
    );
  }
}

class _AnswerDiffView extends StatelessWidget {
  const _AnswerDiffView({required this.input, required this.expected});
  final String input;
  final String expected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diff = diffAnswer(input, expected);
    Widget line(String caption, List<AnswerMark> marks) => Column(
      children: [
        Text(caption, style: Theme.of(context).textTheme.labelMedium),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final mark in marks)
              Text(
                mark.text,
                style: TextStyle(
                  fontSize: 22,
                  color: mark.match ? colors.primary : colors.error,
                ),
              ),
          ],
        ),
      ],
    );
    return Column(
      children: [
        const SizedBox(height: 8),
        line('你的输入', diff.input),
        const SizedBox(height: 6),
        line('对齐后的参考答案', diff.expected),
      ],
    );
  }
}

class _EmptyStudy extends StatelessWidget {
  const _EmptyStudy({
    required this.options,
    required this.kind,
    required this.today,
    required this.onExtra,
    required this.onConfigure,
    required this.onDaily,
    required this.onLibrary,
  });

  final SessionOptions options;
  final EmptyQueueKind? kind;
  final String today;
  final VoidCallback? onExtra;
  final VoidCallback onConfigure;
  final VoidCallback onDaily;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolved = kind;
    if (resolved == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在确认这一轮是完成了，还是没有符合条件的词', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final copy = emptyQueueCopy(resolved, options);
    final finished = resolved == EmptyQueueKind.dailyPlanDone || resolved == EmptyQueueKind.roundComplete;
    final needsLibrary = resolved == EmptyQueueKind.libraryEmpty ||
        resolved == EmptyQueueKind.filteredEmpty ||
        resolved == EmptyQueueKind.modeNeedsContent;
    final icon = finished
        ? Icons.task_alt_rounded
        : needsLibrary
        ? Icons.menu_book_outlined
        : Icons.hourglass_empty_rounded;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Column(
          children: [
            Icon(icon, size: 70, color: colors.primary),
            const SizedBox(height: 18),
            Text(copy.title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(copy.body, textAlign: TextAlign.center),
            if (today.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(today),
            ],
            const SizedBox(height: 24),
            if (finished && options.daily)
              FilledButton(onPressed: onExtra, child: const Text('再学一轮')),
            if (finished && options.daily) const SizedBox(height: 8),
            if (needsLibrary)
              FilledButton(onPressed: onLibrary, child: const Text('去词库补充')),
            if (needsLibrary) const SizedBox(height: 8),
            FilledButton.tonal(onPressed: onConfigure, child: const Text('调整练习方式')),
            if (!options.daily)
              TextButton(onPressed: onDaily, child: const Text('返回每日基础计划')),
            if (!needsLibrary)
              TextButton(onPressed: onLibrary, child: const Text('去词库')),
          ],
        ),
      ),
    );
  }
}
