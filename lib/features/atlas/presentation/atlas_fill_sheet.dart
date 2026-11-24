import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../ai/data/ai_client.dart';
import '../../ai/data/ai_deepseek_client.dart';
import '../../ai/domain/ai_models.dart';
import '../../ai/domain/ai_providers.dart';
import '../../study/domain/providers.dart';
import '../domain/atlas_fill.dart';
import '../domain/atlas_models.dart';

Future<void> showAtlasFill(BuildContext context, Word word) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AtlasFillSheet(word: word),
  );
}

class AtlasFillSheet extends ConsumerStatefulWidget {
  const AtlasFillSheet({super.key, required this.word});
  final Word word;
  @override
  ConsumerState<AtlasFillSheet> createState() => _AtlasFillSheetState();
}

class _AtlasFillSheetState extends ConsumerState<AtlasFillSheet> {
  AtlasEntryDraft? _draft;
  AtlasRecord? _current;
  final _selected = <String>{};
  final _edits = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _edits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final cancellation = AiCancellation();
    try {
      final gateway =
          await (ref.read(aiGatewayProvider) as AiDeferredGateway).ready;
      if (gateway is! AiDeepSeekClient) {
        throw const AiException('not_configured');
      }
      final current = await ref
          .read(databaseProvider)
          .atlasForWord(widget.word.id);
      final draft = await gateway.atlasFill(widget.word, cancellation);
      final open = fillableAtlasFields(current);
      if (!mounted) return;
      setState(() {
        _current = current;
        _draft = draft;
        _selected
          ..clear()
          ..addAll(open);
        for (final controller in _edits.values) {
          controller.dispose();
        }
        _edits
          ..clear()
          ..addAll({
            for (final field in atlasFillFields.keys)
              field: TextEditingController(text: _preview(draft, field)),
          });
      });
    } on AiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _preview(AtlasEntryDraft draft, String field) => switch (field) {
    'senses' =>
      draft.senses
          .map((sense) => '${sense.pos} ${sense.zh} / ${sense.en}')
          .join('\n'),
    'examples' =>
      draft.examples
          .map((example) => '${example.en}\n${example.zh}')
          .join('\n\n'),
    'collocations' => draft.collocations.join('\n'),
    'family' => draft.family.join('\n'),
    'synonyms' => draft.synonyms.join('\n'),
    'antonyms' => draft.antonyms.join('\n'),
    'tip' => draft.tip,
    'cefr' => draft.cefr,
    'topic' => draft.topic,
    'usageNote' => draft.usageNote,
    _ => '',
  };

  AtlasEntryDraft _edited(AtlasEntryDraft draft) {
    List<String> lines(String field) => (_edits[field]?.text ?? '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final exampleLines = (_edits['examples']?.text ?? '').split('\n\n');
    final examples = [
      for (final block in exampleLines)
        if (block.trim().isNotEmpty)
          AtlasExample(
            en: block.split('\n').first.trim(),
            zh: block.split('\n').skip(1).join(' ').trim(),
          ),
    ];
    final senseLines = lines('senses');
    return AtlasEntryDraft(
      id: draft.id,
      word: widget.word.headword,
      ipaUk: draft.ipaUk,
      ipaUs: draft.ipaUs,
      senses: [
        for (final line in senseLines) AtlasSense(pos: '', zh: line, en: ''),
      ],
      examples: examples.isEmpty ? draft.examples : examples,
      collocations: lines('collocations'),
      family: lines('family'),
      synonyms: lines('synonyms'),
      antonyms: lines('antonyms'),
      tip: _edits['tip']?.text.trim() ?? draft.tip,
      cefr: _edits['cefr']?.text.trim() ?? draft.cefr,
      topic: _edits['topic']?.text.trim() ?? draft.topic,
      mediaFlags: 0,
      usageNote: _edits['usageNote']?.text.trim() ?? draft.usageNote,
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(databaseProvider)
          .applyAtlasFill(
            wordId: widget.word.id,
            draft: _edited(draft),
            fields: _selected,
          );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = fillableAtlasFields(_current);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('按图鉴结构补全', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('生成后可以改文字、勾选字段再保存。已有内容和熟悉程度都不会被盖掉。'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _generate,
              child: Text(_busy ? '正在请求 DeepSeek' : '生成预览'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_draft != null)
              for (final field in atlasFillFields.entries) ...[
                CheckboxListTile(
                  value: _selected.contains(field.key),
                  onChanged: open.contains(field.key)
                      ? (value) => setState(() {
                          if (value == true) {
                            _selected.add(field.key);
                          } else {
                            _selected.remove(field.key);
                          }
                        })
                      : null,
                  title: Text(field.value),
                  subtitle: open.contains(field.key)
                      ? null
                      : const Text('已有内容，保持不动'),
                ),
                if (_edits[field.key] != null)
                  TextField(
                    controller: _edits[field.key],
                    maxLines: field.key == 'examples' ? 5 : 2,
                    enabled: open.contains(field.key),
                  ),
              ],
            if (_draft != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || _selected.isEmpty ? null : _save,
                child: const Text('保存勾选的空字段'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
