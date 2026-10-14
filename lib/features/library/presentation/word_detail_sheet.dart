import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';
import '../domain/providers.dart';
import '../../ai/presentation/ai_assistant_sheet.dart';
import '../../ai/domain/ai_models.dart';
import '../../ai/domain/ai_providers.dart';

Future<void> showWordDetail(BuildContext context, Word word) => showModalBottomSheet<void>(
  context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
  builder: (_) => WordDetailSheet(word: word));

class WordDetailSheet extends ConsumerStatefulWidget {
  const WordDetailSheet({super.key, required this.word});
  final Word word;
  @override ConsumerState<WordDetailSheet> createState() => _WordDetailSheetState();
}
class _WordDetailSheetState extends ConsumerState<WordDetailSheet> {
  final _forms = TextEditingController();
  late Future<Map<String, Object?>> _data;
  Future<Map<String, Object?>> _load() async {
    final db = ref.read(databaseProvider), id = widget.word.id;
    final aiRepository = ref.read(aiRepositoryProvider);
    final forms = await db.loadSetting('word_forms:$id') ?? '';
    if (mounted) _forms.text = forms;
    final word = await (db.select(db.words)..where((r) => r.id.equals(id))).getSingleOrNull();
    return {'word': word,
      'ai': word == null ? <String,String>{} : await aiRepository.contents(word),
      'card': await db.cardForWord(id),
      'user': await (db.select(db.userWords)..where((r) => r.wordId.equals(id))).getSingleOrNull(),
      'status': await db.loadSetting('word_status:$id'),
      'logs': await (db.select(db.reviewLogs)..where((r) => r.wordId.equals(id))
        ..orderBy([(r) => drift.OrderingTerm.desc(r.reviewedAt)])..limit(20)).get()};
  }
  @override void initState() { super.initState(); _data = _load(); }
  @override void dispose() { _forms.dispose(); super.dispose(); }
  Future<void> _status(String? value) async {
    await ref.read(databaseProvider).saveSetting('word_status:${widget.word.id}', value);
    ref.invalidate(studyControllerProvider); ref.invalidate(libraryWordsProvider); ref.invalidate(homeCountsProvider);
    if (mounted) setState(() => _data = _load());
  }
  @override Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .80,
    child: FutureBuilder<Map<String, Object?>>(future: _data, builder: (context, snapshot) {
      if (!snapshot.hasData) { return Center(child: snapshot.hasError ? Text('${snapshot.error}') : const CircularProgressIndicator()); }
      final card = snapshot.data!['card'] as StudyCard?;
      final user = snapshot.data!['user'] as UserWord?;
      final logs = snapshot.data!['logs'] as List<ReviewLog>;
      final status = snapshot.data!['status'];
      final word = snapshot.data!['word'] as Word?;
      if (word == null) return const Center(child: Text('词条已删除'));
      final ai = snapshot.data!['ai'] as Map<String,String>;
      return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 28), children: [
        Text(word.korean, style: Theme.of(context).textTheme.headlineSmall),
        Text(word.meaningZh), const SizedBox(height: 10),
        Text('${word.partOfSpeech ?? '未标词性'} · ${word.tags ?? '未标场景'}'),
        if (word.exampleKo != null) ListTile(title: Text(word.exampleKo!), subtitle: Text(word.exampleZh ?? '')),
        if (word.note != null) Text('笔记：${word.note}'),
        FilledButton.icon(onPressed: () async {
          await showAiAssistant(context, word);
          if (mounted) setState(() => _data = _load());
        }, icon: const Icon(Icons.auto_awesome), label: const Text('AI 补全')),
        if (ai.isNotEmpty) const Text('AI 生成·用户已确认'),
        for (final entry in ai.entries) if (!['meaningZh','partOfSpeech','baseForm','exampleKo','exampleZh'].contains(entry.key))
          ExpansionTile(title: Text(aiFieldLabels[entry.key] ?? (entry.key == 'spelling' ? '已确认拼写' : entry.key)), children: [Padding(padding: const EdgeInsets.all(12),
            child: AiPlainText(entry.value, term: word.korean))]),
        const Divider(),
        Text(card == null ? '尚未学习' : '下次复习：${card.due.toLocal().toString().substring(0,16)}'),
        Text('历史认识 ${user?.correctCount ?? 0} 次 · 忘记 ${user?.wrongCount ?? 0} 次'),
        Text(user?.isDifficult == true ? '当前待强化（连续 3 次认识/简单后移出）' : '当前不在待强化队列'),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          ActionChip(label: Text(status == 'known' ? '已设为熟词' : '设为熟词'), onPressed: () => _status('known')),
          ActionChip(label: Text(status == 'suspended' ? '已暂停' : '暂时停学'), onPressed: () => _status('suspended')),
          ActionChip(label: const Text('恢复正常学习'), onPressed: () => _status(null)),
        ]),
        const SizedBox(height: 18),
        Text('词形活用表', style: Theme.of(context).textTheme.titleMedium),
        const Text('每行“形式名称=答案”。请填写已核对的活用形式；应用不会自动推测不规则变化。'),
        const SizedBox(height: 10),
        TextField(controller: _forms, minLines: 3, maxLines: 8, decoration: const InputDecoration(hintText: '敬语现在时=…\n过去时=…')),
        TextButton(onPressed: () async {
          final lines = _forms.text.trim().split('\n').where((s) => s.isNotEmpty).toList();
          if (lines.any((s) => !s.contains('=') || s.split('=').first.trim().isEmpty || s.substring(s.indexOf('=')+1).trim().isEmpty)) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('每行必须有形式名称和答案，用 = 分隔'))); return;
          }
          await ref.read(databaseProvider).saveSetting('word_forms:${widget.word.id}', lines.isEmpty ? null : lines.join('\n'));
          if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('活用表已保存'))); }
        }, child: const Text('保存活用表')),
        const Divider(), Text('最近复习', style: Theme.of(context).textTheme.titleMedium),
        for (final log in logs) ListTile(contentPadding: EdgeInsets.zero,
          title: Text(const ['','忘记','困难','认识','简单'][log.rating.clamp(1,4)]),
          subtitle: Text(log.reviewedAt.toLocal().toString().substring(0,16)), trailing: Text('${log.durationMs ~/ 1000} 秒')),
      ]);
    }),
  );
}
