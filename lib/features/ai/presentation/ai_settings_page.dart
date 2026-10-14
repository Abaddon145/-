import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../study/domain/providers.dart';
import '../data/ai_client.dart';
import '../data/ai_deepseek_client.dart';
import '../domain/ai_providers.dart';
import 'ai_context_picker.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});
  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _address = TextEditingController(),
      _credential = TextEditingController(),
      _apiKey = TextEditingController(),
      _model = TextEditingController(text: 'deepseek-flash');
  String _mode = 'deepseek', _context = '日常韩语', _status = '尚未测试连接';
  bool _busy = false, _loaded = false, _showKey = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      ref.read(aiAddressProvider.future),
      ref.read(aiContextProvider.future),
      ref.read(aiConnectionModeProvider.future),
      ref.read(aiModelProvider.future),
    ]);
    if (!mounted) return;
    setState(() {
      _address.text = values[0];
      _context = values[1];
      _mode = values[2];
      _model.text = values[3];
      _credential.text = ref.read(aiCredentialProvider);
      _apiKey.text = ref.read(aiApiKeyProvider);
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _credential.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save({bool test = false}) async {
    setState(() => _busy = true);
    try {
      final address = _address.text.trim(), apiKey = _apiKey.text.trim();
      final model = _model.text.trim();
      if (_mode == 'proxy') {
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
        if (_credential.text.trim().isEmpty) {
          throw const FormatException('请填写代理访问凭证。');
        }
      } else {
        if (apiKey.isEmpty || apiKey.contains(RegExp(r'\s'))) {
          throw const FormatException(
            '请填写完整的 DeepSeek API Key，不是 Tracking ID。',
          );
        }
        if (model.isEmpty || model.length > 200) {
          throw const FormatException('请填写模型名称。');
        }
      }
      final db = ref.read(databaseProvider);
      await db.saveSetting('ai_connection_mode', _mode);
      if (_mode == 'proxy') await db.saveSetting('ai_proxy_url', address);
      if (_mode == 'deepseek') await db.saveSetting('ai_deepseek_model', model);
      await db.saveSetting('ai_default_context', _context);
      if (!mounted) return;
      // Only non-secret preferences go into Drift. Separate session-only secrets.
      ref.read(aiApiKeyProvider.notifier).state = apiKey;
      ref.read(aiCredentialProvider.notifier).state = _credential.text.trim();
      ref.invalidate(aiAddressProvider);
      ref.invalidate(aiContextProvider);
      ref.invalidate(aiConnectionModeProvider);
      ref.invalidate(aiModelProvider);
      final AiGateway gateway = _mode == 'deepseek'
          ? AiDeepSeekClient(apiKey: apiKey, model: model)
          : AiProxyClient(
              address: address,
              credential: _credential.text.trim(),
            );
      final status = test ? await gateway.health() : '设置已保存；密钥与凭证仅限本次运行会话';
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
                DropdownButtonFormField<String>(
                  initialValue: _mode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '连接方式'),
                  items: const [
                    DropdownMenuItem(
                      value: 'deepseek',
                      child: Text('DeepSeek 直连'),
                    ),
                    DropdownMenuItem(value: 'proxy', child: Text('私有代理')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _mode = value;
                              _status = '尚未测试连接';
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                if (_mode == 'deepseek') ...[
                  const Text(
                    '输入你自己的 DeepSeek API Key 即可，无需部署代理。请求只发送到 api.deepseek.com。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('deepseek-api-key'),
                    controller: _apiKey,
                    enabled: !_busy,
                    obscureText: !_showKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'DeepSeek API Key',
                      hintText: 'sk-…（不是 Tracking ID）',
                      helperText: '仅保存在当前会话；刷新或关闭后需重新输入，不进入备份',
                      helperMaxLines: 3,
                      suffixIcon: IconButton(
                        tooltip: _showKey ? '隐藏密钥' : '显示密钥',
                        onPressed: () => setState(() => _showKey = !_showKey),
                        icon: Icon(
                          _showKey ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('高级选项'),
                    children: [
                      TextField(
                        controller: _model,
                        enabled: !_busy,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: '模型名称',
                          helperText: '默认 deepseek-flash',
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text('连接你自己的私有 AI 代理，模型密钥配置在服务端。'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _address,
                    enabled: !_busy,
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
                    enabled: !_busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '代理访问凭证',
                      helperText: '仅限当前会话，不进入备份',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
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
                const Text(
                  'AI 仅在你点击生成时发送选中的词及必要语境。连接测试只查询服务状态，不生成内容。普通学习可以离线使用。',
                ),
              ],
            ),
    ),
  );
}
