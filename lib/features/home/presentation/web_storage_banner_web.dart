import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../../core/database/web_database_kind.dart';
import '../../study/domain/providers.dart';

class WebStorageBanner extends ConsumerStatefulWidget {
  const WebStorageBanner({super.key});

  @override
  ConsumerState<WebStorageBanner> createState() => _WebStorageBannerState();
}

class _WebStorageBannerState extends ConsumerState<WebStorageBanner> {
  var _otherTab = false;
  var _checkedSplit = false;
  var _showSplit = false;

  @override
  void initState() {
    super.initState();
    webDatabaseKind.addListener(_rebuild);
    unawaited(_watchTabs());
  }

  @override
  void dispose() {
    webDatabaseKind.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _watchTabs() async {
    try {
      final locks = web.window.navigator.locks;
      unawaited(
        locks
            .request(
              'korean-memo-tab',
              web.LockOptions(mode: 'shared'),
              ((JSAny? _) {
                final held = Completer<void>();
                return held.future.toJS;
              }).toJS,
            )
            .toDart,
      );
      final snapshot = await locks.query().toDart;
      final holders = snapshot.held.toDart.where(
        (lock) => lock.name == 'korean-memo-tab',
      );
      if (mounted) setState(() => _otherTab = holders.length > 1);
    } catch (_) {}
  }

  Future<void> _checkSplit() async {
    if (_checkedSplit) return;
    _checkedSplit = true;
    final ua = web.window.navigator.userAgent;
    final ios =
        RegExp('iPad|iPhone|iPod').hasMatch(ua) ||
        (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
    final navigator = web.window.navigator;
    final legacyStandalone =
        navigator.has('standalone') &&
        navigator['standalone'].isA<JSBoolean>() &&
        (navigator['standalone'] as JSBoolean).toDart;
    final installed =
        legacyStandalone ||
        web.window.matchMedia('(display-mode: standalone)').matches;
    if (!ios || !installed) return;
    final db = ref.read(databaseProvider);
    if (await db.loadSetting('storage_split_hint') == 'dismissed') return;
    final reviews = await db
        .customSelect('SELECT COUNT(*) AS amount FROM review_logs')
        .getSingle();
    if (reviews.read<int>('amount') > 0 || !mounted) return;
    setState(() => _showSplit = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedSplit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkSplit());
      });
    }
    final kind = webDatabaseKind.value;
    final unsafe =
        kind == WebDatabaseKind.unsafe || kind == WebDatabaseKind.memory;
    final messages = <Widget>[
      if (unsafe && _otherTab)
        const Text('这个浏览器开着多个词忆。当前存储不能同时写入，请关掉其他标签后再学习。'),
      if (_showSplit)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '主屏幕里的词库和 Safari 里的是分开的。如果之前在 Safari 学过，请先在 Safari 导出备份，再在这里用「恢复学习进度」导入。',
            ),
            TextButton(
              onPressed: () async {
                await ref
                    .read(databaseProvider)
                    .saveSetting('storage_split_hint', 'dismissed');
                if (mounted) setState(() => _showSplit = false);
              },
              child: const Text('知道了'),
            ),
          ],
        ),
    ];
    if (messages.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < messages.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              messages[i],
            ],
          ],
        ),
      ),
    );
  }
}
