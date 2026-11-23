import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_backup_api.dart';
import '../data/cloud_backup_service.dart';

class CloudBackupPage extends ConsumerStatefulWidget {
  const CloudBackupPage({super.key});

  @override
  ConsumerState<CloudBackupPage> createState() => _CloudBackupPageState();
}

class _CloudBackupPageState extends ConsumerState<CloudBackupPage> {
  final _gistId = TextEditingController();
  final _token = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  String _kind = '';
  int _keep = 5;
  int _everyHours = 24;
  bool _afterSession = true;
  bool _includeAi = false;
  bool _githubSaved = false;
  bool _webdavSaved = false;
  String? _lastAt;
  String? _lastError;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _gistId.dispose();
    _token.dispose();
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await ref.read(cloudBackupServiceProvider).loadConfig();
      if (!mounted) return;
      setState(() {
        _kind = config.kind;
        _gistId.text = config.gistId;
        _url.text = config.webdavUrl;
        _user.text = config.webdavUser;
        _keep = const {3, 5, 10}.contains(config.keep) ? config.keep : 5;
        _everyHours = config.everyHours;
        _afterSession = config.afterSession;
        _includeAi = config.includeAi;
        _githubSaved = config.githubSaved;
        _webdavSaved = config.webdavSaved;
        _lastAt = config.lastAt;
        _lastError = config.lastError;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _note('云端设置没有读出来');
    }
  }

  CloudBackupConfig _config() => CloudBackupConfig(
    kind: _kind,
    gistId: _gistId.text,
    webdavUrl: _url.text,
    webdavUser: _user.text,
    keep: _keep,
    everyHours: _everyHours,
    afterSession: _afterSession,
    includeAi: _includeAi,
  );

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(cloudBackupServiceProvider)
          .saveConfig(
            _config(),
            githubToken: _token.text,
            webdavPassword: _password.text,
          );
      _token.clear();
      _password.clear();
      await _load();
      _note('云端设置已保存在这台设备');
    } on CloudBackupException catch (error) {
      _note(error.message);
    } catch (_) {
      _note('云端设置没有保存');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      await _saveQuietly();
      await ref.read(cloudBackupServiceProvider).backup(manual: true);
      await _load();
      _note('已备份到云端');
    } on CloudBackupException catch (error) {
      _note(error.message);
    } catch (_) {
      _note('云端备份没有完成');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveQuietly() => ref
      .read(cloudBackupServiceProvider)
      .saveConfig(
        _config(),
        githubToken: _token.text,
        webdavPassword: _password.text,
      );

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await _saveQuietly();
      final versions = await ref.read(cloudBackupServiceProvider).list();
      if (!mounted) return;
      if (versions.isEmpty) {
        _note('云端还没有备份');
        return;
      }
      final picked = await showDialog<CloudObject>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择要恢复的版本'),
          children: [
            for (final version in versions)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, version),
                child: Text(_versionLabel(version)),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('用云端备份替换本机？'),
          content: const Text('这会清空这台设备上的韩语和英语，再写入所选版本。令牌仍只留在本机。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(cloudBackupServiceProvider).restore(picked);
      _note('已从云端恢复');
    } on CloudBackupException catch (error) {
      _note(error.message);
    } catch (_) {
      _note('云端恢复没有完成');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearSecret(bool github) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(cloudBackupServiceProvider)
          .saveConfig(_config(), clearGithub: github, clearWebdav: !github);
      await _load();
      _note(github ? '已清除这台设备上的 GitHub 令牌' : '已清除这台设备上的 WebDAV 密码');
    } catch (_) {
      _note('没有清除');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _note(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _versionLabel(CloudObject version) {
    final time = version.createdAt?.toLocal();
    if (time == null) return version.name;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('自动云端备份')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'GitHub 令牌请只勾选 gist。勾了 repo 就能读写你的代码仓库。令牌和 WebDAV 密码只留在这台设备，不会写进备份，也不会出现在报错里。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '地址请用 https。页面关掉之后不会在后台自己上传，打开应用或学完一轮时才会备份。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (_lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(_lastError!, style: TextStyle(color: colors.error)),
                ],
                if (_lastAt != null) ...[
                  const SizedBox(height: 8),
                  Text('上次成功：$_lastAt'),
                ],
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: '', label: Text('关闭')),
                    ButtonSegment(value: 'gist', label: Text('Gist')),
                    ButtonSegment(value: 'webdav', label: Text('WebDAV')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() => _kind = value.first),
                ),
                if (_kind == 'gist') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _gistId,
                    decoration: const InputDecoration(
                      labelText: 'Gist 编号',
                      helperText: '留空会在第一次备份时新建一个私有 Gist',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'GitHub 令牌',
                      helperText: _githubSaved
                          ? '这台设备已经保存过令牌。留空表示继续用它。'
                          : '只需要 gist 权限',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy || !_githubSaved
                          ? null
                          : () => _clearSecret(true),
                      child: const Text('清除已保存的令牌'),
                    ),
                  ),
                ],
                if (_kind == 'webdav') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'WebDAV 目录',
                      helperText: '例如 https://example.com/dav/ciyi/',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(labelText: '账号'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: '密码',
                      helperText: _webdavSaved
                          ? '这台设备已经保存过密码。留空表示继续用它。'
                          : '只保存在这台设备',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy || !_webdavSaved
                          ? null
                          : () => _clearSecret(false),
                      child: const Text('清除已保存的密码'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('keep-$_keep'),
                  initialValue: _keep,
                  decoration: const InputDecoration(labelText: '保留最近版本'),
                  items: const [
                    DropdownMenuItem(value: 3, child: Text('3 个')),
                    DropdownMenuItem(value: 5, child: Text('5 个')),
                    DropdownMenuItem(value: 10, child: Text('10 个')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _keep = value ?? 5),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('学完一轮后自动备份'),
                  value: _afterSession,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _afterSession = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('打开应用时检查'),
                  subtitle: Text(
                    _everyHours == 0 ? '不按时间自动备份' : '距上次超过 $_everyHours 小时再备份',
                  ),
                  value: _everyHours > 0,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _everyHours = value ? 24 : 0),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('云端备份包含 AI 数据'),
                  subtitle: const Text('不含 API Key'),
                  value: _includeAi,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _includeAi = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('保存'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy || _kind.isEmpty ? null : _backup,
                  child: const Text('立即备份'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy || _kind.isEmpty ? null : _restore,
                  child: const Text('从云端恢复'),
                ),
              ],
            ),
    );
  }
}
