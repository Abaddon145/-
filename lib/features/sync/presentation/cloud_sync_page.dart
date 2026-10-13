import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_client.dart';
import 'cloud_sync_controller.dart';

class CloudSyncPage extends ConsumerStatefulWidget {
  const CloudSyncPage({super.key});
  @override
  ConsumerState<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends ConsumerState<CloudSyncPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _register = false;
  bool _hidden = true;

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _authenticate() async {
    if (_form.currentState?.validate() != true) return;
    final message = await ref.read(cloudSyncProvider.notifier).authenticate(
      _email.text.trim(), _password.text, register: _register);
    _message(message);
    if (mounted && message.contains('邮箱确认')) setState(() => _register = false);
  }

  Future<void> _choose({required bool local}) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(local ? '将本机数据上传到此账户？' : '恢复此账户的云端数据？'),
      content: Text(local
        ? '包含整个词库、学习记录、收藏、打卡和外观。若云端已有数据，会用本机数据替换。成功后开启自动保存。'
        : '将替换本机词库、学习进度和设置。恢复前会保留一份本机快照，可在设置中撤销恢复。成功后开启自动保存。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(local ? '上传本机' : '恢复云端'))],
    ));
    if (ok != true) return;
    if (local) {
      await ref.read(cloudSyncProvider.notifier).sync(resolveLocal: true);
    } else {
      await ref.read(cloudSyncProvider.notifier).restoreCloud();
    }
  }

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudSyncProvider);
    final colors = Theme.of(context).colorScheme;
    final ready = ref.watch(cloudClientProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('账户与云同步')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.cloud_done_outlined, size: 40, color: colors.primary),
            const SizedBox(height: 14),
            Text('学习，接着上次继续', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('同一账户可在不同设备接续词库、学习记录、收藏、打卡和外观。离线时继续学习，联网后再同步。'),
          ],
        ))),
        const SizedBox(height: 16),
        if (!ready) const Text('云服务初始化失败。请关闭后重新打开应用，本机学习仍可使用。')
        else if (state.userId == null) Form(key: _form, child: Column(children: [
          SegmentedButton<bool>(segments: const [
            ButtonSegment(value: false, label: Text('登录')),
            ButtonSegment(value: true, label: Text('注册')),
          ], selected: {_register}, onSelectionChanged: state.busy ? null
            : (value) => setState(() => _register = value.first)),
          const SizedBox(height: 20),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email], enabled: !state.busy,
            decoration: const InputDecoration(labelText: '邮箱'),
            validator: (value) => value != null && RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim()) ? null : '请输入有效邮箱'),
          const SizedBox(height: 14),
          TextFormField(controller: _password, obscureText: _hidden,
            autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
            enabled: !state.busy, decoration: InputDecoration(labelText: '密码',
              suffixIcon: IconButton(onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
            validator: (value) => value == null || value.isEmpty ? '请输入密码'
              : _register && value.length < 8 ? '请使用至少 8 位密码' : null),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: state.busy ? null : _authenticate,
            child: Text(state.busy ? '正在处理…' : _register ? '注册账户' : '登录'))),
          const SizedBox(height: 12),
          const Text('首次注册需到邮箱确认，确认后返回此处登录。登录不会自动替换本机数据。'),
        ])) else ...[
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.person_outline),
            title: Text(state.email ?? '已登录'), subtitle: const Text('同一邮箱用于其他设备')),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.status, style: Theme.of(context).textTheme.titleMedium),
              if (state.lastSynced != null) ...[
                const SizedBox(height: 8),
                Text('最近检查：${DateTime.tryParse(state.lastSynced!)?.toLocal().toString().split('.').first ?? state.lastSynced}'),
              ],
              if (state.needsChoice) ...[
                const SizedBox(height: 10),
                const Text('请选择本机或云端作为起点。两份数据不会自动合并。'),
              ],
              if (state.busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
            ],
          ))),
          SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('自动同步'),
            subtitle: const Text('打开期间每 30 秒保存；云端有新进度时提示接续'),
            value: state.enabled, onChanged: state.busy ? null
              : (value) => ref.read(cloudSyncProvider.notifier).setEnabled(value)),
          FilledButton.icon(onPressed: state.busy ? null
            : () => ref.read(cloudSyncProvider.notifier).sync(),
            icon: const Icon(Icons.sync), label: const Text('现在同步')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: state.busy ? null : () => _choose(local: true),
            icon: const Icon(Icons.cloud_upload_outlined), label: const Text('保留本机 · 上传到云端')),
          OutlinedButton.icon(onPressed: state.busy ? null : () => _choose(local: false),
            icon: const Icon(Icons.cloud_download_outlined), label: const Text('保留云端 · 恢复到本机')),
          const SizedBox(height: 14),
          TextButton(onPressed: state.busy ? null : () async {
            final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('退出此账户？'),
              content: const Text('自动同步会停止。本机数据仍会保留；在共用设备上请留意本机学习记录。'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出'))]));
            if (ok == true) _message(await ref.read(cloudSyncProvider.notifier).signOut());
          }, child: const Text('退出账户')),
        ],
        const SizedBox(height: 20),
        const Text('云端数据按账户隔离。切换账户不会自动上传本机数据；首次连接需要手动选择。同步采用整份快照，建议仍定期导出文件备份。'),
      ])),
    );
  }
}
