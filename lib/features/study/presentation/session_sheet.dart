import '../../../core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../domain/providers.dart';

Future<void> showSessionSheet(
  BuildContext context, {
  LibraryFilter filter = LibraryFilter.all,
  String tag = '',
}) => showModalBottomSheet<void>(
  sheetAnimationStyle: AppMotion.sheet(context),
  useRootNavigator: true,
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SessionSheet(filter: filter, tag: tag),
);

class SessionSheet extends ConsumerStatefulWidget {
  const SessionSheet({super.key, required this.filter, this.tag = ''});
  final LibraryFilter filter;
  final String tag;
  @override
  ConsumerState<SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<SessionSheet> {
  int? _bookId;
  QueueKind _queue = QueueKind.mixed;
  PracticeMode _mode = PracticeMode.cards;
  StudyDirection _direction = StudyDirection.forward;
  late LibraryFilter _filter;
  final _count = TextEditingController(text: '20');
  final _pos = TextEditingController();
  late TextEditingController _tag;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _filter = widget.filter;
    _tag = TextEditingController(text: widget.tag);
  }

  @override
  void dispose() {
    _count.dispose();
    _pos.dispose();
    _tag.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final count = int.tryParse(_count.text);
    if (count == null || count < 1) {
      setState(() => _error = '请输入大于 0 的本轮数量');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionOptionsProvider.notifier)
          .start(
            SessionOptions(
              daily: false,
              target: count,
              queue: _queue,
              filter: _filter,
              mode: _mode,
              direction: _direction,
              partOfSpeech: _pos.text.trim(),
              tag: _tag.text.trim(),
              bookId: _bookId,
            ),
          );
      ref.invalidate(sessionProgressProvider);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _saving = false;
        });
      }
    }
  }

  bool _customCount = false;

  @override
  Widget build(BuildContext context) {
    final countValue = int.tryParse(_count.text);
    final presetCount = const {10, 20, 50}.contains(countValue);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                children: [
                  Text(
                    '开始一轮练习',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    initialValue: _bookId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '词书'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('全部词书'),
                      ),
                      for (final book
                          in ref.watch(wordBooksProvider).valueOrNull ??
                              const <WordBook>[])
                        DropdownMenuItem<int?>(
                          value: book.id,
                          child: Text(book.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _bookId = value),
                  ),
                  const SizedBox(height: 16),
                  Text('学习内容', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<QueueKind>(
                    segments: const [
                      ButtonSegment(value: QueueKind.mixed, label: Text('混合')),
                      ButtonSegment(
                        value: QueueKind.newWords,
                        label: Text('新词'),
                      ),
                      ButtonSegment(
                        value: QueueKind.reviews,
                        label: Text('复习'),
                      ),
                    ],
                    selected: {_queue},
                    onSelectionChanged: (value) =>
                        setState(() => _queue = value.first),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<LibraryFilter>(
                    initialValue: _filter,
                    decoration: const InputDecoration(labelText: '范围'),
                    items: const [
                      DropdownMenuItem(
                        value: LibraryFilter.all,
                        child: Text('统一词库'),
                      ),
                      DropdownMenuItem(
                        value: LibraryFilter.favorites,
                        child: Text('收藏'),
                      ),
                      DropdownMenuItem(
                        value: LibraryFilter.wrong,
                        child: Text('待强化错词'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _filter = v!),
                  ),
                  const SizedBox(height: 16),
                  Text('练习方式', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in const [
                          (PracticeMode.cards, '翻卡'),
                          (PracticeMode.spelling, '拼写'),
                          (PracticeMode.listening, '听写'),
                          (PracticeMode.cloze, '填空'),
                          (PracticeMode.forms, '词形'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(entry.$2),
                              selected: _mode == entry.$1,
                              onSelected: (_) =>
                                  setState(() => _mode = entry.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('方向', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<StudyDirection>(
                    segments: const [
                      ButtonSegment(
                        value: StudyDirection.forward,
                        label: Text('韩→中'),
                      ),
                      ButtonSegment(
                        value: StudyDirection.reverse,
                        label: Text('中→韩'),
                      ),
                    ],
                    selected: {_direction},
                    onSelectionChanged: (value) =>
                        setState(() => _direction = value.first),
                  ),
                  const SizedBox(height: 16),
                  Text('本轮数量', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 10, label: Text('10')),
                      ButtonSegment(value: 20, label: Text('20')),
                      ButtonSegment(value: 50, label: Text('50')),
                      ButtonSegment(value: 0, label: Text('自定义')),
                    ],
                    selected: {_customCount || !presetCount ? 0 : countValue!},
                    onSelectionChanged: (value) {
                      final picked = value.first;
                      setState(() {
                        _customCount = picked == 0;
                        if (picked != 0) _count.text = '$picked';
                      });
                    },
                  ),
                  if (_customCount || !presetCount) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: '自定义数量'),
                    ),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('更多筛选'),
                    children: [
                      TextField(
                        controller: _pos,
                        decoration: const InputDecoration(
                          labelText: '只练某词性（选填）',
                          hintText: '名词 / 动词',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tag,
                        decoration: const InputDecoration(
                          labelText: '场景标签（选填）',
                          hintText: '工业术语 / 物流 / 邮件 / 日常',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('填空只抽取含原词的已录入例句；词形练习使用详情页中人工录入的活用表。没有合适词条时会提示。'),
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
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _start,
                  child: const Text('开始本轮'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
