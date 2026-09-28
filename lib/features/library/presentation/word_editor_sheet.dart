import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';

Future<bool?> showWordEditor(BuildContext context, {Word? word}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _WordEditorSheet(word: word),
  );
}

class _WordEditorSheet extends ConsumerStatefulWidget {
  const _WordEditorSheet({this.word});

  final Word? word;

  @override
  ConsumerState<_WordEditorSheet> createState() => _WordEditorSheetState();
}

class _WordEditorSheetState extends ConsumerState<_WordEditorSheet> {
  static const _parts = ['名词', '动词', '形容词', '副词', '代词', '助词', '数词', '叹词'];
  final _form = GlobalKey<FormState>();
  late final TextEditingController _korean;
  late final TextEditingController _meaning;
  late final TextEditingController _partOfSpeech;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _korean = TextEditingController(text: widget.word?.korean ?? '');
    _meaning = TextEditingController(text: widget.word?.meaningZh ?? '');
    _partOfSpeech = TextEditingController(text: widget.word?.partOfSpeech ?? '');
  }

  @override
  void dispose() {
    _korean.dispose();
    _meaning.dispose();
    _partOfSpeech.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final word = widget.word;
      if (word == null) {
        await db.addManualWord(
          WordDraft(
            korean: _korean.text,
            meaningZh: _meaning.text,
            partOfSpeech: _partOfSpeech.text,
          ),
        );
      } else {
        await db.updateWord(
          wordId: word.id,
          korean: _korean.text,
          meaningZh: _meaning.text,
          partOfSpeech: _partOfSpeech.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException ? error.message : '保存失败：$error';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: [
            Text(
              widget.word == null ? '录入新单词' : '编辑单词',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '记录韩语、中文释义和词性，即可加入学习计划。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Form(
              key: _form,
              child: Column(
                children: [
                  TextFormField(
                    controller: _korean,
                    autofocus: widget.word == null,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '韩语单词',
                      prefixIcon: Icon(Icons.translate_rounded),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '请输入韩语单词' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _meaning,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '中文释义',
                      prefixIcon: Icon(Icons.menu_book_outlined),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '请输入中文释义' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _partOfSpeech,
                    decoration: const InputDecoration(
                      labelText: '词性',
                      hintText: '例如：名词、动词',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '请标记词性' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                for (final part in _parts)
                  ChoiceChip(
                    label: Text(part),
                    selected: _partOfSpeech.text.trim() == part,
                    onSelected: (_) => setState(() => _partOfSpeech.text = part),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(widget.word == null ? '添加到词库' : '保存修改'),
            ),
          ],
        ),
      ),
    );
  }
}
