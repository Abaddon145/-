import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/database/app_database.dart';
import '../../study/domain/providers.dart';
import 'cloud_backup_api.dart';
import 'cloud_secret_store.dart';

class CloudBackupConfig {
  const CloudBackupConfig({
    this.kind = '',
    this.gistId = '',
    this.webdavUrl = '',
    this.webdavUser = '',
    this.keep = 5,
    this.everyHours = 24,
    this.afterSession = true,
    this.includeAi = false,
    this.githubSaved = false,
    this.webdavSaved = false,
    this.lastAt,
    this.lastError,
  });

  final String kind;
  final String gistId;
  final String webdavUrl;
  final String webdavUser;
  final int keep;
  final int everyHours;
  final bool afterSession;
  final bool includeAi;
  final bool githubSaved;
  final bool webdavSaved;
  final String? lastAt;
  final String? lastError;
}

class CloudBackupService {
  CloudBackupService(this.database, this.secrets, this.api);

  final AppDatabase database;
  final CloudSecretStore secrets;
  final CloudBackupApi api;
  bool _busy = false;

  Future<CloudBackupConfig> loadConfig() async {
    final values = await _settings([
      'backup_cloud_kind',
      'backup_cloud_gist_id',
      'backup_cloud_webdav_url',
      'backup_cloud_webdav_user',
      'backup_cloud_keep',
      'backup_cloud_every_hours',
      'backup_cloud_after_session',
      'backup_cloud_include_ai',
      'backup_cloud_last_at',
      'backup_cloud_last_error',
    ]);
    final github = await secrets.read(CloudSecretStore.github);
    final webdav = await secrets.read(CloudSecretStore.webdav);
    return CloudBackupConfig(
      kind: values['backup_cloud_kind'] ?? '',
      gistId: values['backup_cloud_gist_id'] ?? '',
      webdavUrl: values['backup_cloud_webdav_url'] ?? '',
      webdavUser: values['backup_cloud_webdav_user'] ?? '',
      keep: clampCloudKeep(
        int.tryParse(values['backup_cloud_keep'] ?? '') ?? 5,
      ),
      everyHours: int.tryParse(values['backup_cloud_every_hours'] ?? '') ?? 24,
      afterSession: values['backup_cloud_after_session'] != 'false',
      includeAi: values['backup_cloud_include_ai'] == 'true',
      githubSaved: github != null && github.isNotEmpty,
      webdavSaved: webdav != null && webdav.isNotEmpty,
      lastAt: values['backup_cloud_last_at'],
      lastError: values['backup_cloud_last_error'],
    );
  }

  Future<void> saveConfig(
    CloudBackupConfig config, {
    String? githubToken,
    String? webdavPassword,
    bool clearGithub = false,
    bool clearWebdav = false,
  }) async {
    await database.saveSetting(
      'backup_cloud_kind',
      config.kind == 'gist' || config.kind == 'webdav' ? config.kind : '',
    );
    await database.saveSetting('backup_cloud_gist_id', config.gistId.trim());
    await database.saveSetting(
      'backup_cloud_webdav_url',
      config.webdavUrl.trim(),
    );
    await database.saveSetting(
      'backup_cloud_webdav_user',
      config.webdavUser.trim(),
    );
    await database.saveSetting(
      'backup_cloud_keep',
      '${clampCloudKeep(config.keep)}',
    );
    await database.saveSetting(
      'backup_cloud_every_hours',
      '${config.everyHours <= 0 ? 0 : config.everyHours}',
    );
    await database.saveSetting(
      'backup_cloud_after_session',
      '${config.afterSession}',
    );
    await database.saveSetting(
      'backup_cloud_include_ai',
      '${config.includeAi}',
    );
    if (clearGithub) await secrets.delete(CloudSecretStore.github);
    if (clearWebdav) await secrets.delete(CloudSecretStore.webdav);
    final token = githubToken?.trim();
    if (token != null && token.isNotEmpty) {
      await secrets.write(CloudSecretStore.github, token);
    }
    final password = webdavPassword?.trim();
    if (password != null && password.isNotEmpty) {
      await secrets.write(CloudSecretStore.webdav, password);
    }
  }

  Future<void> afterSession() async {
    try {
      final config = await loadConfig();
      if (!config.afterSession || config.kind.isEmpty) return;
      await backup();
    } catch (_) {}
  }

  Future<void> maybeScheduled() async {
    try {
      final config = await loadConfig();
      if (config.kind.isEmpty || config.everyHours <= 0) return;
      final last = DateTime.tryParse(config.lastAt ?? '');
      if (last != null &&
          DateTime.now().toUtc().difference(last.toUtc()).inHours <
              config.everyHours) {
        return;
      }
      await backup();
    } catch (_) {}
  }

  Future<void> backup({bool manual = false}) async {
    if (_busy) {
      if (manual) throw const CloudBackupException('上一份云端备份还在进行');
      return;
    }
    _busy = true;
    try {
      final config = await loadConfig();
      if (config.kind != 'gist' && config.kind != 'webdav') {
        if (manual) throw const CloudBackupException('还没有选择云端位置');
        return;
      }
      final snapshot = await database.createBackupSnapshot(
        includeAi: config.includeAi,
      );
      final body = jsonEncode(snapshot);
      if (config.kind == 'gist') {
        final token = await secrets.read(CloudSecretStore.github) ?? '';
        if (token.isEmpty) {
          throw const CloudBackupException('还没有填写 GitHub 令牌');
        }
        final id = await api.uploadGist(
          token: token,
          gistId: config.gistId,
          body: body,
          keep: config.keep,
        );
        await database.saveSetting('backup_cloud_gist_id', id);
      } else {
        final password = await secrets.read(CloudSecretStore.webdav) ?? '';
        if (config.webdavUser.isEmpty || password.isEmpty) {
          throw const CloudBackupException('还没有填写 WebDAV 账号或密码');
        }
        await api.uploadWebDav(
          directory: parseWebDavDirectory(config.webdavUrl),
          user: config.webdavUser,
          password: password,
          body: body,
          keep: config.keep,
        );
      }
      await database.saveSetting(
        'backup_cloud_last_at',
        DateTime.now().toUtc().toIso8601String(),
      );
      await database.saveSetting('backup_cloud_last_error', null);
    } on CloudBackupException catch (error) {
      await database.saveSetting('backup_cloud_last_error', error.message);
      if (manual) rethrow;
    } catch (_) {
      const message = '云端备份没有完成';
      await database.saveSetting('backup_cloud_last_error', message);
      if (manual) throw const CloudBackupException(message);
    } finally {
      _busy = false;
    }
  }

  Future<List<CloudObject>> list() async {
    final config = await loadConfig();
    if (config.kind == 'gist') {
      final token = await secrets.read(CloudSecretStore.github) ?? '';
      if (token.isEmpty || config.gistId.isEmpty) {
        throw const CloudBackupException('还没有 GitHub 令牌或备份编号');
      }
      return api.listGist(token: token, gistId: config.gistId);
    }
    if (config.kind == 'webdav') {
      final password = await secrets.read(CloudSecretStore.webdav) ?? '';
      if (password.isEmpty) {
        throw const CloudBackupException('还没有填写 WebDAV 密码');
      }
      return api.listWebDav(
        directory: parseWebDavDirectory(config.webdavUrl),
        user: config.webdavUser,
        password: password,
      );
    }
    throw const CloudBackupException('还没有选择云端位置');
  }

  Future<void> restore(CloudObject object) async {
    final config = await loadConfig();
    final String text;
    if (config.kind == 'gist') {
      final token = await secrets.read(CloudSecretStore.github) ?? '';
      text = await api.download(object, token: token);
    } else if (config.kind == 'webdav') {
      final password = await secrets.read(CloudSecretStore.webdav) ?? '';
      text = await api.download(
        object,
        user: config.webdavUser,
        password: password,
      );
    } else {
      throw const CloudBackupException('还没有选择云端位置');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const CloudBackupException('云端备份格式无效');
    }
    await database.restoreBackupSnapshot(decoded.cast<String, dynamic>());
  }

  Future<Map<String, String?>> _settings(List<String> keys) async {
    final values = <String, String?>{};
    for (final key in keys) {
      values[key] = await database.loadSetting(key);
    }
    return values;
  }
}

final cloudSecretStoreProvider = Provider<CloudSecretStore>(
  (ref) => const SecureCloudSecretStore(),
);

final cloudHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final cloudBackupServiceProvider = Provider<CloudBackupService>((ref) {
  return CloudBackupService(
    ref.watch(databaseProvider),
    ref.watch(cloudSecretStoreProvider),
    CloudBackupApi(ref.watch(cloudHttpClientProvider)),
  );
});
