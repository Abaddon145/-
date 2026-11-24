import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_motion.dart';
import '../../../services/fsrs_service.dart';
import '../../study/data/study_repository.dart';
import '../../study/domain/providers.dart';
import '../data/atlas_audio_player.dart';
import '../domain/atlas_models.dart';
import '../domain/atlas_providers.dart';
import '../domain/atlas_quiz.dart';
import '../domain/ui_sounds.dart';

class AtlasStudyPage extends ConsumerStatefulWidget {
  const AtlasStudyPage({super.key});

  @override
  ConsumerState<AtlasStudyPage> createState() => _AtlasStudyPageState();
}

class _AtlasStudyPageState extends ConsumerState<AtlasStudyPage> {
  final _player = AtlasAudioPlayer();
  final _answer = TextEditingController();
  final _clock = Stopwatch();
  AtlasSession? _session;
  Map<int, AtlasQuizWord> _words = {};
  List<AtlasQuizWord> _pool = [];
  AtlasQuestion? _question;
  String? _hint;
  bool _usedHint = false;
  bool _busy = false;
  StudyRating? _pending;
  bool _correct = false;
  String? _error;
  int _firstCorrect = 0;
  int _firstTotal = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _answer.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final options = ref.read(sessionOptionsProvider);
    final queue = await db.loadAtlasQueue(
      options,
      DateTime.now(),
      reviewsOnly: options.queue == QueueKind.reviews,
    );
    final words = [
      for (final item in queue)
        AtlasQuizWord(
          id: item.id,
          headword: item.headword,
          meaning: item.meaning,
          pos: item.pos,
          cefr: item.cefr,
          hasImage: (item.mediaFlags & atlasMediaImage) != 0,
          example: item.example,
          stability: item.stability,
          atlasId: item.atlasId,
        ),
    ];
    final reviews = words
        .where(
          (word) =>
              word.stability > 0 ||
              !queue.any((item) => item.id == word.id && item.isNew),
        )
        .toList();
    final fresh = [
      for (final item in queue)
        if (item.isNew) words.firstWhere((word) => word.id == item.id),
    ];
    final due = [
      for (final item in queue)
        if (!item.isNew) words.firstWhere((word) => word.id == item.id),
    ];
    if (!mounted) return;
    setState(() {
      _words = {for (final word in words) word.id: word};
      _pool = words;
      _session = AtlasSession(
        steps: buildAtlasJourney(
          reviews: due.isEmpty ? reviews : due,
          fresh: fresh,
        ),
      );
      _loaded = true;
      _prepare();
    });
    ref.read(studyHasCardProvider.notifier).state = words.isNotEmpty;
  }

  void _prepare() {
    final step = _session?.current;
    _answer.clear();
    _hint = null;
    _usedHint = false;
    _pending = null;
    _clock
      ..reset()
      ..start();
    if (step == null) {
      _question = null;
      return;
    }
    final word = _words[step.wordId];
    if (word == null || step.phase == AtlasStepKind.intro) {
      _question = null;
      if (word != null) _speak(word, example: false);
      return;
    }
    _question = buildAtlasQuestion(word: word, kind: step.kind, pool: _pool);
    if (step.kind == AtlasQuestionKind.listen) _speak(word, example: false);
  }

  Future<void> _speak(AtlasQuizWord word, {required bool example}) async {
    final accent = ref.read(englishAccentProvider).valueOrNull ?? 'en-US';
    final flags = _pool.where((item) => item.id == word.id).isEmpty
        ? 0
        : (word.hasImage ? atlasMediaImage : 0);
    final record = await ref.read(databaseProvider).atlasForWord(word.id);
    final media = record?.mediaFlags ?? flags;
    final atlasId = record?.atlasId ?? word.atlasId;
    final url = example
        ? ((media & atlasMediaExample) == 0
              ? null
              : atlasAssetUrl('ex', atlasId))
        : preferredWordAudioUrl(
            atlasId: atlasId,
            mediaFlags: media,
            accent: accent,
          );
    if (url != null) {
      final bytes = await ref.read(atlasMediaCacheProvider).get(Uri.parse(url));
      if (bytes != null && await _player.play(bytes)) return;
    }
    await ref
        .read(ttsServiceProvider)
        .speakKorean(
          example && word.example.isNotEmpty ? word.example : word.headword,
          learningLanguage: 'en',
          englishAccent: accent,
        );
  }

  Future<void> _chime(UiSoundKind kind) async {
    final enabled = ref.read(uiSoundsProvider).valueOrNull ?? true;
    if (!shouldPlayUiSound(
      enabled: enabled,
      reduceMotion: AppMotion.reduced(context),
    )) {
      return;
    }
    await _player.play(uiSoundWav(kind));
  }

  Future<void> _choose(String value) async {
    final question = _question;
    final step = _session?.current;
    if (question == null || step == null || _busy || _pending != null) return;
    final correct =
        value.trim().toLowerCase() == question.answer.trim().toLowerCase();
    await _offer(step, correct);
  }

  Future<void> _submitSpelling() async {
    final question = _question;
    final step = _session?.current;
    if (question == null || step == null || _pending != null) return;
    final correct =
        _answer.text.trim().toLowerCase() ==
        question.answer.trim().toLowerCase();
    await _offer(step, correct);
  }

  Future<void> _offer(AtlasStep step, bool correct) async {
    final scored = _session?.writesScore(step) ?? false;
    final rating = gradeAtlasAnswer(
      correct: correct,
      elapsed: _clock.elapsed,
      usedHint: _usedHint,
      kind: step.kind,
    );
    if (scored) {
      _firstTotal += 1;
      if (correct && rating != StudyRating.again) _firstCorrect += 1;
    }
    await _chime(correct ? UiSoundKind.correct : UiSoundKind.wrong);
    setState(() {
      _correct = correct;
      _pending = scored ? capRatingForHint(rating, usedHint: _usedHint) : null;
    });
    if (!scored) {
      _advance(correct);
    }
  }

  Future<void> _commit(StudyRating rating) async {
    final step = _session?.current;
    final word = step == null ? null : _words[step.wordId];
    if (step == null || word == null || _busy) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final row = await (db.select(
        db.words,
      )..where((item) => item.id.equals(word.id))).getSingle();
      final repository = StudyRepository(
        db,
        ref.read(fsrsServiceProvider),
        options: ref.read(sessionOptionsProvider),
      );
      await repository.submitRating(
        word: row,
        rating: capRatingForHint(rating, usedHint: _usedHint),
        duration: _clock.elapsed,
      );
      _advance(_correct);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _advance(bool correct) {
    final step = _session?.current;
    final word = step == null ? null : _words[step.wordId];
    _session?.answer(correct: correct, hasImage: word?.hasImage ?? false);
    setState(_prepare);
    ref.read(studyHasCardProvider.notifier).state =
        !(_session?.isComplete ?? true);
  }

  Future<void> _undo() async {
    final word = await ref
        .read(databaseProvider)
        .undoLastReview(DateTime.now(), ref.read(activeLanguageProvider));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(word == null ? '没有可撤销的评分' : '已撤销「${word.headword}」的评分'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final step = session?.current;
    final word = step == null ? null : _words[step.wordId];
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('图鉴测验'),
        actions: [
          IconButton(
            tooltip: '撤销一次评分',
            onPressed: _undo,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + inset),
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : session == null || session.isComplete || word == null
              ? _done()
              : ListView(
                  children: [
                    Text(
                      step!.phase == AtlasStepKind.intro
                          ? '初见'
                          : (step.scored ? '回忆' : '再练一次，不计入成绩'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 12),
                    if (step.phase == AtlasStepKind.intro)
                      _intro(word)
                    else
                      _recall(word),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _done() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('这一轮先到这里', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('首次作答 $_firstCorrect / $_firstTotal。重练不计入成绩。'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => ref.read(sessionOptionsProvider.notifier).daily(),
          child: const Text('回到原来的学习方式'),
        ),
      ],
    );
  }

  Widget _intro(AtlasQuizWord word) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(word.headword, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(word.meaning),
        if (word.example.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(word.example),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            _chime(UiSoundKind.flip);
            _advance(true);
          },
          child: const Text('记住了，开始回忆'),
        ),
      ],
    );
  }

  Widget _recall(AtlasQuizWord word) {
    final question = _question;
    if (question == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.prompt,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        if (question.kind == AtlasQuestionKind.spelling) ...[
          TextField(
            controller: _answer,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '拼写',
              helperText: _hint == null ? null : '提示：$_hint',
            ),
            onSubmitted: (_) => _submitSpelling(),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pending != null
                ? null
                : () {
                    setState(() {
                      _usedHint = true;
                      _hint = revealSpellingHint(question.answer, _hint ?? '');
                    });
                  },
            child: const Text('提示一个字母'),
          ),
          FilledButton(
            onPressed: _pending == null ? _submitSpelling : null,
            child: const Text('提交'),
          ),
        ] else
          for (final option in question.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: _pending == null ? () => _choose(option) : null,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(option),
                ),
              ),
            ),
        if (_pending != null) ...[
          const SizedBox(height: 12),
          Text(_correct ? '记下来了' : '这次先记下，稍后换种题再练'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final rating in StudyRating.values)
                ChoiceChip(
                  label: Text(switch (rating) {
                    StudyRating.again => '忘记',
                    StudyRating.hard => '模糊',
                    StudyRating.good => '认识',
                    StudyRating.easy => '简单',
                  }),
                  selected: _pending == rating,
                  onSelected: _usedHint && rating.index > StudyRating.hard.index
                      ? null
                      : (_) => setState(() => _pending = rating),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : () => _commit(_pending!),
            child: Text(_busy ? '正在保存' : '写入这次评分'),
          ),
        ],
      ],
    );
  }
}
