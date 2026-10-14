import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';
import '../../library/domain/providers.dart';
import '../data/ai_client.dart';
import '../data/ai_repository.dart';
import '../domain/ai_models.dart';
import '../domain/ai_providers.dart';
import 'ai_context_picker.dart';

Future<void> showAiAssistant(
  BuildContext context,
  Word word, {
  bool explain = false,
  AiSuggestion? suggestion,
  bool batch = false,
  String? taskItemId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => AiAssistantSheet(
    word: word,
    explain: explain,
    initialSuggestion: suggestion,
    batch: batch,
    taskItemId: taskItemId,
  ),
);

class AiAssistantSheet extends ConsumerStatefulWidget {
  const AiAssistantSheet({
    super.key,
    required this.word,
    this.explain = false,
    this.initialSuggestion,
    this.batch = false,
    this.taskItemId,
  });
  final Word word;
  final bool explain, batch;
  final AiSuggestion? initialSuggestion;
  final String? taskItemId;
  @override
  ConsumerState<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends ConsumerState<AiAssistantSheet> {
  late Word _word;
  String _context = '日常韩语', _style = 'default';
  int _exampleCount = 1;
  bool _busy = false, _loading = true, _editing = false, _saved = false;
  String? _error, _expectedSnapshot, _spelling;
  AiSuggestion? _suggestion;
  final _candidates = <AiSuggestion>[];
  final _selected = <String>{};
  final _fields = <String, TextEditingController>{};
  Map<String, String> _existing = {};
  AiCancellation? _cancel;
  @override
  void initState() {
    super.initState();
    _word = widget.word;
    _editing = !widget.explain;
    _load();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repository = ref.read(aiRepositoryProvider);
    final defaultContext = ref.read(aiContextProvider.future);
    try {
      final current = await repository.word(_word.id);
      if (current == null) throw const AiException('deleted');
      final extra = await repository.contents(current);
      final context = widget.initialSuggestion?.context ?? await defaultContext;
      if (!mounted) return;
      _word = current;
      _existing = {
        ...aiWordSnapshot(
          current,
        ).map((k, v) => MapEntry(k, v?.toString() ?? '')),
        ...extra,
      };
      _context = context;
      final cached =
          widget.initialSuggestion ??
          (widget.explain ? await repository.cached(_request()) : null);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (cached != null) _choose(cached);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  AiRequest _request() => AiRequest(
    requestId: const Uuid().v4(),
    word: _word,
    context: _context,
    type: widget.explain ? 'explain' : 'complete',
    style: _style,
    exampleCount: _exampleCount,
  );
  void _choose(AiSuggestion suggestion) {
    _suggestion = suggestion;
    if (!_candidates.any((s) => s.requestId == suggestion.requestId)) {
      _candidates.add(suggestion);
    }
    _selected.clear();
    _spelling = null;
    _saved = false;
    for (final key in aiFieldLabels.keys) {
      (_fields[key] ??= TextEditingController()).text = suggestion.fieldText(
        key,
      );
      if (suggestion.fieldText(key).isNotEmpty &&
          aiFieldMissing(key, _existing[key]) &&
          !(key == 'meaningZh' &&
              (suggestion.needsMoreContext || suggestion.suspectedTypo))) {
        _selected.add(key);
      }
    }
    if (widget.batch) _selected.removeWhere((key) => key != 'meaningZh');
  }

  Future<void> _generate({String? style}) async {
    if (_busy) return;
    final repository = ref.read(aiRepositoryProvider),
        gateway = ref.read(aiGatewayProvider);
    _cancel = AiCancellation();
    if (style != null) _style = style;
    final request = _request();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await gateway.generate(request, _cancel!);
      _cancel!.check();
      await repository.store(request, result, itemId: widget.taskItemId);
      if (mounted) {
        setState(() {
          _choose(result);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeContext() async {
    final context = await chooseAiContext(this.context, _context);
    if (!mounted || context == null) return;
    setState(() {
      _context = context;
      _suggestion = null;
      _candidates.clear();
      _selected.clear();
      _error = null;
    });
    if (widget.explain) {
      final cached = await ref.read(aiRepositoryProvider).cached(_request());
      if (mounted && cached != null) setState(() => _choose(cached));
    }
  }

  Future<void> _save() async {
    final suggestion = _suggestion;
    if (suggestion == null || _busy || _saved) return;
    final repository = ref.read(aiRepositoryProvider);
    try {
      var spellingConfirmed = false;
      if (_spelling != null) {
        spellingConfirmed =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('单独确认拼写变更'),
                content: Text(
                  '原词：${_word.korean}\n候选：$_spelling\n请依据原表和语境核对。保存时将检查重复词。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确认修改原词'),
                  ),
                ],
              ),
            ) ==
            true;
        if (!mounted || !spellingConfirmed) return;
      }
      final edited = suggestion.edited({
        for (final entry in _fields.entries) entry.key: entry.value.text,
      });
      setState(() {
        _busy = true;
        _error = null;
      });
      await repository.save(
        suggestion.requestId,
        edited,
        Set.of(_selected),
        expectedSnapshot: _expectedSnapshot,
        spelling: _spelling,
        spellingConfirmed: spellingConfirmed,
        itemId: widget.taskItemId,
      );
      if (!mounted) return;
      ref.invalidate(libraryWordsProvider);
      setState(() {
        _saved = true;
      });
    } on AiConflict catch (conflict) {
      if (!mounted) return;
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('原词已修改，请重新确认'),
              content: SingleChildScrollView(
                child: Text(
                  '生成时：${suggestion.result['originalTerm']}\n当前：${conflict.current.korean}\n当前中文：${conflict.current.meaningZh}\n建议中文：${_fields['meaningZh']?.text ?? ''}\n\n将加载当前内容，请重新勾选要保存的字段。',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('重新对比'),
                ),
              ],
            ),
          ) ==
          true;
      if (confirmed && mounted) {
        final extra = await repository.contents(conflict.current);
        if (!mounted) return;
        setState(() {
          _word = conflict.current;
          _expectedSnapshot = aiSnapshotJson(_word);
          _existing = {
            ...aiWordSnapshot(
              _word,
            ).map((k, v) => MapEntry(k, v?.toString() ?? '')),
            ...extra,
          };
          _selected.clear();
          _error = '已加载最新内容。请重新勾选字段并保存。';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = _suggestion;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    '${widget.explain ? 'AI 解释' : 'AI 补全词条'} · ${_word.korean}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _changeContext,
                    icon: const Icon(Icons.tune),
                    label: Text('语境：$_context'),
                  ),
                  const Text('AI 生成建议，请核对后选择保存。仅发送当前词条及必要语境。'),
                  if (!widget.batch)
                    DropdownButtonFormField<int>(
                      initialValue: _exampleCount,
                      decoration: const InputDecoration(labelText: '例句数量（每组）'),
                      items: [
                        for (var n = 1; n <= 3; n++)
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: _busy
                          ? null
                          : (n) => setState(() => _exampleCount = n!),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _generate(),
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(suggestion == null ? '生成建议' : '重新生成候选'),
                      ),
                      if (_busy)
                        TextButton(
                          onPressed: () => _cancel?.cancel(),
                          child: const Text('取消请求'),
                        ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_candidates.length > 1) ...[
                    const Text('比较候选（点击切换，保留原生成内容）'),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (var i = 0; i < _candidates.length; i++)
                          ChoiceChip(
                            label: Text('候选 ${i + 1}'),
                            selected:
                                _candidates[i].requestId ==
                                suggestion?.requestId,
                            onSelected: _busy
                                ? null
                                : (_) =>
                                      setState(() => _choose(_candidates[i])),
                          ),
                      ],
                    ),
                    for (var i = 0; i < _candidates.length; i++)
                      Text('${i + 1}：${_candidates[i].fieldText('meaningZh')}'),
                  ],
                  if (suggestion != null) ...[
                    Text(
                      'AI 生成 · ${suggestion.model} · ${suggestion.generatedAt.toLocal().toString().substring(0, 16)}',
                    ),
                    if (suggestion.suspectedTypo || suggestion.needsMoreContext)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${suggestion.suspectedTypo ? '疑似拼写异常。原词不会自动修改。\n' : ''}${suggestion.needsMoreContext ? '需要更多语境，请查看候选义项。\n' : ''}${suggestion.spellings.join(' / ')}',
                          ),
                        ),
                      ),
                    if (widget.explain) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final action in const [
                            ('simpler', '更简单'),
                            ('work', '工作场景'),
                            ('confusing', '易混淆词'),
                            ('example', '例句解析'),
                          ])
                            ActionChip(
                              label: Text(action.$2),
                              onPressed: _busy
                                  ? null
                                  : () => _generate(style: action.$1),
                            ),
                        ],
                      ),
                      for (final key in const [
                        'meaningZh',
                        'collocations',
                        'exampleKo',
                        'exampleZh',
                        'workExampleKo',
                        'workExampleZh',
                        'usageNote',
                        'grammarNote',
                        'ambiguityNotes',
                        'confusingWords',
                        'terminologyNote',
                      ])
                        if (suggestion.fieldText(key).isNotEmpty)
                          ExpansionTile(
                            initiallyExpanded: [
                              'meaningZh',
                              'collocations',
                              'exampleKo',
                              'workExampleKo',
                            ].contains(key),
                            title: Text(aiFieldLabels[key]!),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: AiPlainText(
                                    suggestion.fieldText(key),
                                    term: _word.korean,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      TextButton(
                        onPressed: () => setState(() => _editing = !_editing),
                        child: Text(_editing ? '收起保存编辑' : '预览并选择保存内容'),
                      ),
                    ],
                    if (_editing) ...[
                      const Divider(),
                      const Text('原内容 → 建议；缺失字段默认勾选，已有内容需主动选择。'),
                      for (final key in aiFieldLabels.keys)
                        if (!widget.batch || key == 'meaningZh')
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(aiFieldLabels[key]!),
                                    value: _selected.contains(key),
                                    onChanged: _busy || _saved
                                        ? null
                                        : (value) => setState(() {
                                            if (value == true) {
                                              _selected.add(key);
                                            } else {
                                              _selected.remove(key);
                                            }
                                          }),
                                  ),
                                  Text(
                                    '原内容：${_existing[key]?.isNotEmpty == true ? _existing[key] : '缺失'}',
                                  ),
                                  TextField(
                                    controller: _fields[key],
                                    enabled: !_busy && !_saved,
                                    minLines: 1,
                                    maxLines: 5,
                                    maxLength: aiListFields.contains(key)
                                        ? 3000
                                        : aiFieldLimits[key],
                                    decoration: InputDecoration(
                                      labelText: 'AI 建议（可编辑）',
                                      helperText: aiListFields.contains(key)
                                          ? '每行一项，最多 6 项，每项 500 字'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      if (!widget.batch && suggestion.spellings.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey(suggestion.requestId),
                          initialValue: _spelling,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '拼写变更（单独确认）',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('保留原词拼写'),
                            ),
                            for (final spelling in suggestion.spellings)
                              DropdownMenuItem(
                                value: spelling,
                                child: Text(spelling),
                              ),
                          ],
                          onChanged: _busy || _saved
                              ? null
                              : (value) => setState(() => _spelling = value),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed:
                            _busy ||
                                _saved ||
                                (_selected.isEmpty && _spelling == null)
                            ? null
                            : _save,
                        child: Text(
                          _saved
                              ? '已保存 · AI 生成·用户已确认'
                              : '保存选中的 ${_selected.length} 个字段',
                        ),
                      ),
                      if (_saved) const Text('复习计划、学习次数与打卡保持不变。'),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}

/// Highlight only literal target text. Model HTML/Markdown is never executed.
class AiPlainText extends StatelessWidget {
  const AiPlainText(this.text, {super.key, required this.term});
  final String text, term;
  @override
  Widget build(BuildContext context) {
    if (term.isEmpty || !text.contains(term)) return SelectableText(text);
    final parts = text.split(term);
    return SelectableText.rich(
      TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            TextSpan(text: parts[i]),
            if (i < parts.length - 1)
              TextSpan(
                text: term,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
          ],
        ],
      ),
    );
  }
}
