import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../atlas/domain/atlas_providers.dart';
import '../../atlas/presentation/atlas_thumb.dart';
import '../../study/domain/providers.dart';
import '../domain/typing_meter.dart';

class TypingStudioPage extends ConsumerStatefulWidget {
  const TypingStudioPage({super.key});
  @override
  ConsumerState<TypingStudioPage> createState() => _TypingStudioPageState();
}

class _TypingStudioPageState extends ConsumerState<TypingStudioPage> {
  final _input = TextEditingController();
  final _meter = TypingMeter();
  String _source = 'book';
  String _mode = 'word';
  List<AtlasQueueWord> _words = [];
  var _index = 0;
  var _started = false;
  final _watch = Stopwatch();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final books = ref.read(wordBooksProvider).valueOrNull ?? const <WordBook>[];
    final bookId = _source == 'book' && books.isNotEmpty
        ? books.first.id
        : null;
    final words = await ref
        .read(databaseProvider)
        .typingSources(
          language: ref.read(activeLanguageProvider),
          source: _source,
          bookId: bookId,
        );
    if (!mounted) return;
    setState(() {
      _words = words;
      _index = 0;
      _input.clear();
      _started = false;
      _watch.reset();
    });
  }

  String _expected(AtlasQueueWord word) {
    if (_mode == 'sentence') {
      return word.example.isEmpty ? word.headword : word.example;
    }
    return word.headword;
  }

  Future<void> _submit() async {
    if (_words.isEmpty) return;
    if (!_started) {
      _started = true;
      _watch.start();
    }
    final word = _words[_index];
    final elapsed = _watch.elapsedMilliseconds;
    _watch.reset();
    _meter.commit(
      typed: _input.text,
      expected: _expected(word),
      elapsedMs: elapsed == 0 ? 1 : elapsed,
    );
    _input.clear();
    setState(() => _index = (_index + 1) % _words.length);
    _watch.start();
  }

  @override
  Widget build(BuildContext context) {
    final word = _words.isEmpty ? null : _words[_index];
    final accent = ref.watch(englishAccentProvider).valueOrNull ?? 'en-US';
    final language = ref.watch(activeLanguageProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('打字工作室')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            const Text('打字只练习输出，不改变熟悉程度。速度按每 5 个正确字符计 1 词。'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _source,
              decoration: const InputDecoration(labelText: '词源'),
              items: const [
                DropdownMenuItem(value: 'recent', child: Text('最近学过')),
                DropdownMenuItem(value: 'wrong', child: Text('错词')),
                DropdownMenuItem(value: 'favorite', child: Text('收藏')),
                DropdownMenuItem(value: 'book', child: Text('当前词书')),
              ],
              onChanged: (value) => setState(() => _source = value ?? 'book'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: '练习'),
              items: const [
                DropdownMenuItem(value: 'word', child: Text('看义打单词')),
                DropdownMenuItem(value: 'copy', child: Text('抄写例句')),
                DropdownMenuItem(value: 'dictation', child: Text('听写整句')),
              ],
              onChanged: (value) => setState(() => _mode = value ?? 'word'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('载入词条')),
            if (word != null) ...[
              const SizedBox(height: 16),
              if (language == 'en' && word.atlasId.isNotEmpty)
                AtlasThumb(atlasId: word.atlasId, size: 120),
              const SizedBox(height: 8),
              Text(
                _mode == 'word'
                    ? word.meaning
                    : (_mode == 'copy' ? _expected(word) : '听完后写下整句'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_mode == 'dictation')
                TextButton(
                  onPressed: () => ref
                      .read(ttsServiceProvider)
                      .speakKorean(
                        _expected(word),
                        learningLanguage: language,
                        englishAccent: accent,
                      ),
                  child: const Text('播放'),
                ),
              TextField(
                controller: _input,
                decoration: const InputDecoration(labelText: '输入'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _submit, child: const Text('下一题')),
              const SizedBox(height: 12),
              Text(
                '${_meter.wpm.toStringAsFixed(1)} 词/分钟 · 准确率 ${(_meter.accuracy * 100).round()}%',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
