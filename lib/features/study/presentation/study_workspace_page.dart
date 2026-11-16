import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/language/learning_language.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../library/domain/providers.dart';
import '../../library/presentation/word_editor_sheet.dart';
import '../../library/presentation/word_detail_sheet.dart';
import '../domain/practice.dart';
import '../../../services/fsrs_service.dart';
import '../../../services/tts_service.dart';
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
  int? _spokenWordId;
  Timer? _resumeTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _answer.dispose();
    super.dispose();
  }

  void _armResume(DateTime? at) {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (at == null) return;
    _resumeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!at.isAfter(DateTime.now())) {
        timer.cancel();
        _resumeTimer = null;
        ref.read(studyControllerProvider.notifier).load();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(studyControllerProvider.notifier)
        .setAppActive(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      final resumeAt = ref.read(studyControllerProvider).resumeAt;
      if (resumeAt != null && !resumeAt.isAfter(DateTime.now())) {
        ref.read(studyControllerProvider.notifier).load();
      }
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
      _sessionKey = options.key;
      _wordId = word?.id;
      _answer.clear();
      _correct = null;
    }
    final hasCard = word != null;
    if (ref.read(studyHasCardProvider) != hasCard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(studyHasCardProvider) != hasCard) {
          ref.read(studyHasCardProvider.notifier).state = hasCard;
        }
      });
    }
    if (options.mode == PracticeMode.listening &&
        word != null &&
        _spokenWordId != word.id) {
      _spokenWordId = word.id;
      final spoken = practiceItem(word, options).spoken;
      final spokenId = word.id;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _spokenWordId != spokenId) return;
        final rate =
            double.tryParse(
              await ref
                      .read(databaseProvider)
                      .loadSetting(
                        scopedSetting(
                          ref.read(activeLanguageProvider),
                          'speech_rate',
                        ),
                      ) ??
                  '',
            ) ??
            .45;
        if (!mounted || _spokenWordId != spokenId) return;
        await ref
            .read(ttsServiceProvider)
            .speakKorean(
              spoken,
              rate: rate,
              learningLanguage: ref.read(activeLanguageProvider),
            );
      });
    }
    ref.listen(studyControllerProvider, (previous, next) {
      if (next.resumeAt != previous?.resumeAt) _armResume(next.resumeAt);
      final notice = next.notice;
      if (notice == null || notice == previous?.notice) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notice)));
    });
    final quiz = options.mode != PracticeMode.cards;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '结束学习',
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.close_rounded),
          ),
          title: Text(options.daily ? '今日学习' : '本轮练习'),
          actions: [
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
                          state.resumeAt == null
                              ? '本轮完成，或暂时没有符合条件的词'
                              : learningResumeLabel(
                                  DateTime.now(),
                                  state.resumeAt!,
                                ),
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
                        if (options.daily)
                          FilledButton(
                            onPressed: state.isLoading
                                ? null
                                : () async {
                                    final count =
                                        ref
                                            .read(dailyPlanProgressProvider)
                                            .valueOrNull
                                            ?.settings
                                            .newWordsPerDay ??
                                        DailyPlanSettings.defaultNewWords;
                                    await controller.startExtraRound(count);
                                  },
                            child: const Text('再学一轮'),
                          ),
                        if (options.daily) const SizedBox(height: 8),
                        FilledButton.tonal(
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      options.daily
                          ? ref
                                .watch(studyRoundProgressProvider)
                                .when(
                                  skipLoadingOnReload: true,
                                  skipLoadingOnRefresh: true,
                                  data: (p) =>
                                      _progress('每日新词', p.done, p.target),
                                  loading: () => const SizedBox(height: 41),
                                  error: (_, _) => const SizedBox(),
                                )
                          : ref
                                .watch(sessionProgressProvider)
                                .when(
                                  skipLoadingOnReload: true,
                                  skipLoadingOnRefresh: true,
                                  data: (p) =>
                                      _progress('本轮练习', p.done, p.target),
                                  loading: () => const SizedBox(height: 41),
                                  error: (_, _) => const SizedBox(),
                                ),
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: AnimatedSwitcher(
                            duration: AppMotion.duration(context, 200),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.04, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: LayoutBuilder(
                              key: ValueKey('${word.id}:${options.key}'),
                              builder: (context, constraints) => InkWell(
                                onTap: quiz || state.isRevealed
                                    ? null
                                    : controller.reveal,
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(18),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight - 36,
                                    ),
                                    child: Builder(
                                      builder: (context) {
                                        final item = practiceItem(
                                          word,
                                          options,
                                          forms: forms,
                                          formIndex:
                                              ref
                                                  .watch(
                                                    sessionProgressProvider,
                                                  )
                                                  .valueOrNull
                                                  ?.done ??
                                              0,
                                        );
                                        Future<void> grade() async {
                                          FocusScope.of(context).unfocus();
                                          setState(
                                            () => _correct = answerMatches(
                                              _answer.text,
                                              item.answer,
                                            ),
                                          );
                                          controller.reveal();
                                        }

                                        final rawHeight =
                                            constraints.maxHeight - 36;
                                        final contentHeight = rawHeight.isFinite
                                            ? rawHeight.clamp(0.0, 10000.0)
                                            : 0.0;
                                        return Stack(
                                          children: [
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                minWidth:
                                                    (constraints.maxWidth - 36)
                                                        .clamp(
                                                          0,
                                                          double.infinity,
                                                        ),
                                                minHeight: contentHeight,
                                              ),
                                              child: Column(
                                                children: [
                                                  SizedBox(
                                                    height:
                                                        contentHeight * 0.30,
                                                  ),
                                                  Semantics(
                                                    localeForSubtree:
                                                        hangulPattern.hasMatch(
                                                          item.question,
                                                        )
                                                        ? const Locale('ko')
                                                        : null,
                                                    child: Text(
                                                      item.question,
                                                      locale:
                                                          hangulPattern
                                                              .hasMatch(
                                                                item.question,
                                                              )
                                                          ? const Locale('ko')
                                                          : null,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .headlineMedium
                                                          ?.copyWith(
                                                            fontSize: reading
                                                                .wordSize,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            height: reading
                                                                .lineHeight,
                                                          ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                  if (word
                                                          .partOfSpeech
                                                          ?.isNotEmpty ==
                                                      true)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 10,
                                                          ),
                                                      child: Chip(
                                                        label: Text(
                                                          word.partOfSpeech!,
                                                        ),
                                                      ),
                                                    ),
                                                  if (word.language == 'en' &&
                                                      word.ipa?.isNotEmpty ==
                                                          true)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 8,
                                                          ),
                                                      child: Text(
                                                        word.ipa!,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: Theme.of(
                                                          context,
                                                        ).textTheme.titleMedium,
                                                      ),
                                                    ),
                                                  if (word.language != 'en' &&
                                                      word.hanja?.isNotEmpty ==
                                                          true)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 8,
                                                          ),
                                                      child: Text(
                                                        word.hanja!,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ),
                                                  if (word.language != 'en' &&
                                                      word
                                                              .topikLevel
                                                              ?.isNotEmpty ==
                                                          true)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 6,
                                                          ),
                                                      child: Text(
                                                        'TOPIK ${word.topikLevel}',
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ),
                                                  const SizedBox(height: 12),
                                                  IconButton.filledTonal(
                                                    tooltip: '播放发音',
                                                    onPressed: () async {
                                                      final rate =
                                                          double.tryParse(
                                                            await ref
                                                                    .read(
                                                                      databaseProvider,
                                                                    )
                                                                    .loadSetting(
                                                                      scopedSetting(
                                                                        ref.read(
                                                                          activeLanguageProvider,
                                                                        ),
                                                                        'speech_rate',
                                                                      ),
                                                                    ) ??
                                                                '',
                                                          ) ??
                                                          .45;
                                                      await ref
                                                          .read(
                                                            ttsServiceProvider,
                                                          )
                                                          .speakKorean(
                                                            item.spoken,
                                                            rate: rate,
                                                            learningLanguage:
                                                                ref.read(
                                                                  activeLanguageProvider,
                                                                ),
                                                          );
                                                    },
                                                    icon: const Icon(
                                                      Icons.volume_up_rounded,
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    onPressed:
                                                        state.isSubmitting
                                                        ? null
                                                        : () => _explain(word),
                                                    icon: const Icon(
                                                      Icons.auto_awesome,
                                                    ),
                                                    label: const Text('AI 解释'),
                                                  ),
                                                  if (quiz) ...[
                                                    const SizedBox(height: 18),
                                                    TextField(
                                                      controller: _answer,
                                                      enabled: _correct == null,
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText: '输入答案',
                                                          ),
                                                      onSubmitted: (_) =>
                                                          grade(),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    if (_correct == null)
                                                      OutlinedButton(
                                                        onPressed: grade,
                                                        child: const Text(
                                                          '检查答案',
                                                        ),
                                                      )
                                                    else ...[
                                                      Text(
                                                        _correct!
                                                            ? '回答正确'
                                                            : '需要再记一次',
                                                        style: TextStyle(
                                                          color: _correct!
                                                              ? colors.primary
                                                              : colors.error,
                                                        ),
                                                      ),
                                                      Text(
                                                        '参考答案：${item.answer}',
                                                        locale:
                                                            hangulPattern
                                                                .hasMatch(
                                                                  item.answer,
                                                                )
                                                            ? const Locale('ko')
                                                            : null,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        _correct!
                                                            ? '建议记为「认识」。记得很吃力可选「困难」，毫不费力可选「简单」。'
                                                            : '如果只是差一点，可选「困难」，不必把整张卡片记成忘记。',
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      if (!_correct!)
                                                        Wrap(
                                                          children: [
                                                            for (final mark
                                                                in answerHighlight(
                                                                  _answer.text,
                                                                  item.answer,
                                                                ))
                                                              Text(
                                                                mark.text,
                                                                locale:
                                                                    hangulPattern
                                                                        .hasMatch(
                                                                          mark.text,
                                                                        )
                                                                    ? const Locale(
                                                                        'ko',
                                                                      )
                                                                    : null,
                                                                style: TextStyle(
                                                                  fontSize: 22,
                                                                  color:
                                                                      mark.correct
                                                                      ? colors
                                                                            .primary
                                                                      : colors
                                                                            .error,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                    ],
                                                  ] else if (state
                                                      .isRevealed) ...[
                                                    const Divider(
                                                      indent: 48,
                                                      endIndent: 48,
                                                      height: 32,
                                                    ),
                                                    RevealContent(
                                                      child: Column(
                                                        children: [
                                                          StudyMeaning(
                                                            key: ValueKey(
                                                              word.id,
                                                            ),
                                                            text: item.answer,
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .headlineSmall
                                                                ?.copyWith(
                                                                  fontSize: reading
                                                                      .meaningSize,
                                                                  height: reading
                                                                      .lineHeight,
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.onSurface,
                                                                ),
                                                          ),
                                                          if (word
                                                                      .exampleKo
                                                                      ?.isNotEmpty ==
                                                                  true ||
                                                              word
                                                                      .exampleZh
                                                                      ?.isNotEmpty ==
                                                                  true)
                                                            Container(
                                                              width: double
                                                                  .infinity,
                                                              margin:
                                                                  const EdgeInsets.only(
                                                                    top: 12,
                                                                  ),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    14,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .surfaceContainerLow,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      16,
                                                                    ),
                                                              ),
                                                              child: Column(
                                                                children: [
                                                                  if (word
                                                                          .exampleKo
                                                                          ?.isNotEmpty ==
                                                                      true)
                                                                    Semantics(
                                                                      localeForSubtree: Locale(
                                                                        word.language ==
                                                                                'en'
                                                                            ? 'en'
                                                                            : 'ko',
                                                                      ),
                                                                      child: SelectableText(
                                                                        word.exampleKo!,
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                      ),
                                                                    ),
                                                                  if (word
                                                                          .exampleZh
                                                                          ?.isNotEmpty ==
                                                                      true)
                                                                    Padding(
                                                                      padding: const EdgeInsets.symmetric(
                                                                        vertical:
                                                                            10,
                                                                      ),
                                                                      child: Text(
                                                                        word.exampleZh!,
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                          if (word.language !=
                                                              'en')
                                                            ref
                                                                .watch(
                                                                  studyWordFormsProvider(
                                                                    word.id,
                                                                  ),
                                                                )
                                                                .when(
                                                                  skipLoadingOnReload:
                                                                      true,
                                                                  data: (forms) =>
                                                                      forms
                                                                          .trim()
                                                                          .isEmpty
                                                                      ? const SizedBox.shrink()
                                                                      : Padding(
                                                                          padding: const EdgeInsets.only(
                                                                            top:
                                                                                12,
                                                                          ),
                                                                          child: Text(
                                                                            forms,
                                                                            textAlign:
                                                                                TextAlign.center,
                                                                          ),
                                                                        ),
                                                                  loading: () =>
                                                                      const SizedBox.shrink(),
                                                                  error: (_, _) =>
                                                                      const SizedBox.shrink(),
                                                                ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  IconButton(
                                                    tooltip: '收藏',
                                                    onPressed: () async {
                                                      final db = ref.read(
                                                        databaseProvider,
                                                      );
                                                      await db.setFavorite(
                                                        word.id,
                                                        !favorite,
                                                      );
                                                      ref.invalidate(
                                                        studyFavoriteProvider(
                                                          word.id,
                                                        ),
                                                      );
                                                      ref.invalidate(
                                                        libraryWordsProvider,
                                                      );
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              favorite
                                                                  ? '已取消收藏'
                                                                  : '已收藏',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    icon: AnimatedSwitcher(
                                                      duration:
                                                          AppMotion.duration(
                                                            context,
                                                            160,
                                                          ),
                                                      transitionBuilder:
                                                          (child, animation) =>
                                                              ScaleTransition(
                                                                scale:
                                                                    animation,
                                                                child: child,
                                                              ),
                                                      child: Icon(
                                                        favorite
                                                            ? Icons.star_rounded
                                                            : Icons
                                                                  .star_border_rounded,
                                                        key: ValueKey(favorite),
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    tooltip: '更多',
                                                    icon: const Icon(
                                                      Icons.more_horiz,
                                                    ),
                                                    onSelected: (value) async {
                                                      if (value == 'edit') {
                                                        await _edit(word);
                                                      } else {
                                                        controller
                                                            .pauseForPanel();
                                                        try {
                                                          await showWordDetail(
                                                            context,
                                                            word,
                                                          );
                                                        } finally {
                                                          if (mounted &&
                                                              controller
                                                                  .mounted) {
                                                            controller
                                                                .resumeFromPanel();
                                                          }
                                                        }
                                                      }
                                                    },
                                                    itemBuilder: (_) => const [
                                                      PopupMenuItem(
                                                        value: 'edit',
                                                        child: Text('编辑单词'),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'detail',
                                                        child: Text('单词详情'),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
                          controller.rate(rating);
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  bool _typing() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>() !=
      null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_typing()) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      _key();
      return KeyEventResult.handled;
    }
    final ratings = <LogicalKeyboardKey, StudyRating>{
      LogicalKeyboardKey.digit1: StudyRating.again,
      LogicalKeyboardKey.digit2: StudyRating.hard,
      LogicalKeyboardKey.digit3: StudyRating.good,
      LogicalKeyboardKey.digit4: StudyRating.easy,
    };
    final rating = ratings[key];
    if (rating == null) return KeyEventResult.ignored;
    _key(rating);
    return KeyEventResult.handled;
  }

  void _key([StudyRating? rating]) {
    if (_typing()) return;
    final state = ref.read(studyControllerProvider);
    final controller = ref.read(studyControllerProvider.notifier);
    final quiz = ref.read(sessionOptionsProvider).mode != PracticeMode.cards;
    if (state.word == null || state.isSubmitting || state.isLoading) return;
    if (rating == null) {
      if (!state.isRevealed && !quiz) controller.reveal();
      if (state.isRevealed) controller.rate(StudyRating.good);
      return;
    }
    if (quiz && _correct == null) return;
    if (state.isRevealed || _correct != null) controller.rate(rating);
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
