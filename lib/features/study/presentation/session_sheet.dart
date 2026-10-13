import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../domain/providers.dart';

Future<void> showSessionSheet(BuildContext context, {LibraryFilter filter = LibraryFilter.all, String tag = ''}) =>
  showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true,
    showDragHandle: true, builder: (_) => SessionSheet(filter: filter, tag: tag));

class SessionSheet extends ConsumerStatefulWidget {
  const SessionSheet({super.key, required this.filter, this.tag = ''});
  final LibraryFilter filter;
  final String tag;
  @override ConsumerState<SessionSheet> createState() => _SessionSheetState();
}
class _SessionSheetState extends ConsumerState<SessionSheet> {
  QueueKind _queue = QueueKind.mixed;
  PracticeMode _mode = PracticeMode.cards;
  StudyDirection _direction = StudyDirection.forward;
  late LibraryFilter _filter;
  final _count = TextEditingController(text: '20');
  final _pos = TextEditingController();
  late TextEditingController _tag;
  bool _saving = false;
  String? _error;
  @override void initState() { super.initState(); _filter = widget.filter; _tag = TextEditingController(text: widget.tag); }
  @override void dispose() { _count.dispose(); _pos.dispose(); _tag.dispose(); super.dispose(); }
  Future<void> _start() async {
    final count = int.tryParse(_count.text);
    if (count == null || count < 1) { setState(() => _error = '请输入大于 0 的本轮数量'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(sessionOptionsProvider.notifier).start(SessionOptions(daily: false, target: count,
        queue: _queue, filter: _filter, mode: _mode, direction: _direction, partOfSpeech: _pos.text.trim(), tag: _tag.text.trim()));
      ref.invalidate(sessionProgressProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) { if (mounted) { setState(() { _error = '$error'; _saving = false; }); } }
  }
  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.viewInsetsOf(context).bottom + 22),
    child: SizedBox(height: MediaQuery.sizeOf(context).height * .65,
      child: ListView(children: [
        Text('开始一轮练习', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<QueueKind>(initialValue: _queue, decoration: const InputDecoration(labelText: '学习内容'),
          items: const [DropdownMenuItem(value: QueueKind.mixed, child: Text('混合学习')), DropdownMenuItem(value: QueueKind.newWords, child: Text('只学新词')), DropdownMenuItem(value: QueueKind.reviews, child: Text('只复习到期词'))], onChanged: (v) => setState(() => _queue = v!)),
        const SizedBox(height: 12),
        DropdownButtonFormField<LibraryFilter>(initialValue: _filter, decoration: const InputDecoration(labelText: '范围'),
          items: const [DropdownMenuItem(value: LibraryFilter.all, child: Text('统一词库')), DropdownMenuItem(value: LibraryFilter.favorites, child: Text('收藏')), DropdownMenuItem(value: LibraryFilter.wrong, child: Text('待强化错词'))], onChanged: (v) => setState(() => _filter = v!)),
        const SizedBox(height: 12),
        DropdownButtonFormField<PracticeMode>(initialValue: _mode, decoration: const InputDecoration(labelText: '练习方式'),
          items: const [DropdownMenuItem(value: PracticeMode.cards, child: Text('翻卡自评')), DropdownMenuItem(value: PracticeMode.spelling, child: Text('拼写')), DropdownMenuItem(value: PracticeMode.listening, child: Text('听写')), DropdownMenuItem(value: PracticeMode.cloze, child: Text('例句填空')), DropdownMenuItem(value: PracticeMode.forms, child: Text('词形活用'))], onChanged: (v) => setState(() => _mode = v!)),
        const SizedBox(height: 12),
        DropdownButtonFormField<StudyDirection>(initialValue: _direction, decoration: const InputDecoration(labelText: '方向'),
          items: const [DropdownMenuItem(value: StudyDirection.forward, child: Text('韩语→释义 / 英语')), DropdownMenuItem(value: StudyDirection.reverse, child: Text('释义 / 英语→韩语（英韩拼写可练英文）'))], onChanged: (v) => setState(() => _direction = v!)),
        const SizedBox(height: 12),
        TextField(controller: _count, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: '本轮数量（不限 100）')),
        const SizedBox(height: 12),
        TextField(controller: _pos, decoration: const InputDecoration(labelText: '只练某词性（选填）', hintText: '名词 / 动词')),
        const SizedBox(height: 12),
        TextField(controller: _tag, decoration: const InputDecoration(labelText: '场景标签（选填）', hintText: '工业术语 / 物流 / 邮件 / 日常')),
        const SizedBox(height: 10),
        const Text('填空只抽取含原词的已录入例句；词形练习使用详情页中人工录入的活用表。没有合适词条时会提示。'),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _start, child: const Text('开始本轮')),
      ])),
  );
}
