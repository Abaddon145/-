import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../study/domain/providers.dart';
import '../data/ai_client.dart';
import '../domain/ai_providers.dart';
import 'ai_context_picker.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});
  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _address = TextEditingController(),
      _credential = TextEditingController();
  String _context = '日常韩语', _status = '尚未测试连接';
  bool _busy = false, _loaded = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final addressFuture = ref.read(aiAddressProvider.future);
    final contextFuture = ref.read(aiContextProvider.future);
    final address = await addressFuture, context = await contextFuture;
    if (!mounted) return;
    setState(() {
      _address.text = address;
      _context = context;
      _credential.text = ref.read(aiCredentialProvider);
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _credential.dispose();
    super.dispose();
  }

  Future<void> _save({bool test = false}) async {
    setState(() => _busy = true);
    try {
      final address = _address.text.trim();
      final uri = Uri.tryParse(address);
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.scheme != 'https' &&
              !(uri.scheme == 'http' &&
                  ['localhost', '127.0.0.1'].contains(uri.host)))) {
        throw const FormatException('请填写 HTTPS 代理地址；本机调试可用 localhost。');
      }
      final db = ref.read(databaseProvider);
      await db.saveSetting('ai_proxy_url', address);
      await db.saveSetting('ai_default_context', _context);
      if (!mounted) return;
      ref.read(aiCredentialProvider.notifier).state = _credential.text;
      ref.invalidate(aiAddressProvider);
      ref.invalidate(aiContextProvider);
      final status = test
          ? await AiProxyClient(
              address: address,
              credential: _credential.text,
            ).health()
          : '设置已保存；凭证仅限本次运行会话';
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 设置')),
    body: SafeArea(
      child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('连接你自己的私有 AI 代理。模型 API 密钥仅配置在服务端。'),
                const SizedBox(height: 16),
                TextField(
                  controller: _address,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '代理地址',
                    hintText: 'https://your-proxy.example',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _credential,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '代理访问凭证',
                    helperText: '关闭应用或刷新网页后需重新输入；不进入备份',
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('默认语境'),
                  subtitle: Text(_context),
                  trailing: const Icon(Icons.tune),
                  onTap: _busy
                      ? null
                      : () async {
                          final value = await chooseAiContext(
                            context,
                            _context,
                          );
                          if (mounted && value != null) {
                            setState(() => _context = value);
                          }
                        },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : () => _save(),
                      child: const Text('保存设置'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _save(test: true),
                      child: const Text('连接测试'),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text('服务状态：$_status'),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('清理 AI 缓存'),
                  subtitle: const Text('清理未保存且不属于批量任务的建议。已确认内容与任务保留。'),
                  onTap: () async {
                    await ref.read(aiRepositoryProvider).clearCache();
                    if (mounted) setState(() => _status = 'AI 缓存已清理');
                  },
                ),
                const SizedBox(height: 16),
                const Text('AI 仅在你点击生成时发送选中的词及必要语境。普通学习可以离线使用。'),
              ],
            ),
    ),
  );
}
