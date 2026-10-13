import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../../core/theme/reading_preferences.dart';
import '../../library/domain/providers.dart';
import '../../statistics/domain/providers.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';
import '../data/cloud_client.dart';
import '../domain/sync_snapshot.dart';

class CloudSyncState {
  const CloudSyncState({this.userId, this.email, this.busy = false,
    this.enabled = false, this.hasRemote = false, this.needsChoice = false,
    this.status = '登录后可同步词库、学习进度和打卡', this.lastSynced,
    this.lastSavedAt, this.revision, this.pendingLocal = false,
    this.failed = false, this.cloudChanged = false});
  final String? userId;
  final String? email;
  final bool busy;
  final bool enabled;
  final bool hasRemote;
  final bool needsChoice;
  final String status;
  final String? lastSynced;
  final String? lastSavedAt;
  final int? revision;
  final bool pendingLocal;
  final bool failed;
  final bool cloudChanged;

  String get label {
    if (userId == null) return '本机模式';
    if (busy) return '正在同步';
    if (failed) return '同步待重试';
    if (cloudChanged) return '云端有更新';
    if (needsChoice) return '需选择进度';
    if (pendingLocal) return enabled ? '本机记录待保存' : '有本机更新';
    if (!enabled) return '自动保存已暂停';
    return lastSynced == null ? '等待首次同步' : '已与云端一致';
  }

  CloudSyncState copyWith({bool? busy, bool? enabled, bool? hasRemote,
    bool? needsChoice, String? status, String? lastSynced, String? lastSavedAt,
    int? revision, bool? pendingLocal, bool? failed, bool? cloudChanged}) => CloudSyncState(
    userId: userId, email: email, busy: busy ?? this.busy,
    enabled: enabled ?? this.enabled, hasRemote: hasRemote ?? this.hasRemote,
    needsChoice: needsChoice ?? this.needsChoice, status: status ?? this.status,
    lastSynced: lastSynced ?? this.lastSynced,
    lastSavedAt: lastSavedAt ?? this.lastSavedAt, revision: revision ?? this.revision,
    pendingLocal: pendingLocal ?? this.pendingLocal, failed: failed ?? this.failed,
    cloudChanged: cloudChanged ?? this.cloudChanged);
}

class CloudSyncController extends StateNotifier<CloudSyncState> {
  CloudSyncController(this.database, this.client, this.onRestore,
      {this.prepareLocal, this.autoSaveDelay = const Duration(seconds: 5)})
      : super(const CloudSyncState()) {
    if (client == null) return;
    _dataChanges = database.tableUpdates(TableUpdateQuery.onAllTables([
      database.words, database.wordBooks, database.wordBookWords,
      database.studyCards, database.reviewLogs, database.userWords,
      database.dailyStatistics,
    ])).map<void>((_) {}).listen((_) => _markLocalChange(), onError: _localWatchFailed);
    _settingsChanges = database.select(database.appSettings).watch().map((rows) {
      final current = {for (final row in rows.where((row) => portableSetting(row.key)))
        row.key: (row.value, row.updatedAt)};
      final previous = _portableSettings;
      final changed = previous != null && (previous.length != current.length ||
        current.entries.any((entry) => previous[entry.key] != entry.value));
      // Compare immutable values directly: avoid JSON-copying large backgrounds
      // every time the device-only cloud timestamp changes.
      _portableSettings = current;
      return changed;
    }).listen((changed) { if (changed) _markLocalChange(); }, onError: _localWatchFailed);
    _auth = client!.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != state.userId) unawaited(_loadAccount());
    }, onError: (Object error) {
      if (mounted) {
        state = state.copyWith(failed: true, status: '登录状态更新失败，请重新登录');
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && state.enabled) unawaited(sync(automatic: true));
    });
    unawaited(_loadAccount());
  }

  final AppDatabase database;
  final SupabaseClient? client;
  final void Function() onRestore;
  final Future<void> Function()? prepareLocal;
  final Duration autoSaveDelay;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<void>? _dataChanges;
  StreamSubscription<bool>? _settingsChanges;
  Timer? _timer;
  Timer? _autoSaveTimer;
  Map<String, (String, DateTime)>? _portableSettings;
  int _generation = 0;
  bool _restoring = false;
  DateTime? _lastResend;
  String? _lastResendEmail;
  int _epoch = 0;
  int? _baselineRevision;
  String? _baselineDigest;
  bool _foreground = true;
  Object? lastError;

  bool _valid(int epoch, String user) => mounted && _epoch == epoch &&
      client?.auth.currentUser?.id == user;

  Future<void> _loadAccount() async {
    _autoSaveTimer?.cancel();
    final epoch = ++_epoch;
    final user = client?.auth.currentUser;
    _baselineRevision = null;
    _baselineDigest = null;
    state = CloudSyncState(userId: user?.id, email: user?.email,
      busy: user != null, status: user == null
      ? '登录后可同步词库、学习进度和打卡' : '正在检查云端进度…');
    if (user == null) return;
    try {
      final raw = await database.loadSetting('cloud_binding');
      final binding = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      if (!_valid(epoch, user.id)) return;
      if (binding?['userId'] == user.id) {
        _baselineRevision = binding!['revision'] as int?;
        _baselineDigest = binding['digest'] as String?;
        state = state.copyWith(enabled: binding['enabled'] == true,
          lastSynced: binding['lastSynced'] as String?,
          lastSavedAt: binding['lastSavedAt'] as String?, revision: _baselineRevision);
        final localDigest = snapshotDigest(await _local());
        if (!_valid(epoch, user.id)) return;
        state = state.copyWith(pendingLocal: localDigest != _baselineDigest);
      }
      final remote = await _remoteMetadata(user.id);
      if (!_valid(epoch, user.id)) return;
      state = state.copyWith(busy: false, hasRemote: remote != null,
        needsChoice: _baselineRevision == null,
        cloudChanged: _baselineRevision != null && remote != null &&
          remote['revision'] != _baselineRevision,
        status: _baselineRevision == null
          ? (remote == null ? '首次使用：先上传本机数据' : '发现云端进度，请选择保留哪份数据')
          : '已连接，可检查最新进度');
      if (state.enabled) unawaited(sync(automatic: true));
    } catch (error) {
      lastError = error;
      if (_valid(epoch, user.id)) {
        state = state.copyWith(busy: false,
          failed: true,
          status: '无法连接云端，本机学习可继续；联网后再试');
      }
    }
  }

  Future<Map<String, dynamic>?> _remoteMetadata(String userId) => client!
    .from('korean_memo_snapshots').select('revision,digest,updated_at')
    .eq('user_id', userId).maybeSingle().timeout(const Duration(seconds: 20));

  Future<Map<String, dynamic>> _local() async {
    final data = portableSnapshot(await database.createBackupSnapshot());
    if (utf8.encode(jsonEncode(data)).length > 20 * 1024 * 1024) {
      throw const FormatException('同步数据超过 20 MB，请减小自定义背景后重试');
    }
    return data;
  }

  Future<void> _remember(Map<String, dynamic> meta,
      {bool? enable, int? capturedGeneration}) async {
    _baselineRevision = (meta['revision'] as num).toInt();
    _baselineDigest = meta['digest'] as String;
    final now = DateTime.now().toUtc().toIso8601String();
    final pending = capturedGeneration != null && capturedGeneration != _generation;
    lastError = null;
    state = state.copyWith(hasRemote: true, needsChoice: false,
      enabled: enable ?? state.enabled, lastSynced: now,
      lastSavedAt: meta['updated_at'] as String?, revision: _baselineRevision,
      pendingLocal: pending, failed: false, cloudChanged: false,
      status: pending ? '本机还有新记录，等待下一次保存' : '进度已同步');
    await database.saveSetting('cloud_binding', jsonEncode({
      'userId': state.userId, 'revision': _baselineRevision,
      'digest': _baselineDigest, 'enabled': state.enabled, 'lastSynced': now,
      'lastSavedAt': state.lastSavedAt,
    }));
  }

  Future<void> setEnabled(bool enabled) async {
    if (state.busy || state.userId == null) return;
    if (enabled && _baselineRevision == null) {
      state = state.copyWith(needsChoice: true, status: '请先上传本机或恢复云端数据');
      return;
    }
    state = state.copyWith(enabled: enabled);
    if (!enabled) _autoSaveTimer?.cancel();
    await database.saveSetting('cloud_binding', jsonEncode({
      'userId': state.userId, 'revision': _baselineRevision,
      'digest': _baselineDigest, 'enabled': enabled, 'lastSynced': state.lastSynced,
      'lastSavedAt': state.lastSavedAt,
    }));
    if (enabled) await sync(automatic: true);
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) _autoSaveTimer?.cancel();
    if (foreground && state.enabled) unawaited(sync(automatic: true));
  }

  Future<void> pauseForLocalRestore() async {
    _autoSaveTimer?.cancel();
    _epoch++;
    _baselineDigest = null;
    _baselineRevision = null;
    state = state.copyWith(enabled: false, busy: false, needsChoice: true,
      failed: false, cloudChanged: false, pendingLocal: false,
      status: '已暂停同步，恢复完成后请重新选择本机或云端数据');
    await database.saveSetting('cloud_binding', null);
  }

  // resolveLocal is only used after an explicit overwrite confirmation.
  Future<void> sync({bool resolveLocal = false, bool automatic = false}) async {
    if (state.busy || state.userId == null || client == null) return;
    final user = state.userId!;
    final epoch = _epoch;
    _autoSaveTimer?.cancel();
    state = state.copyWith(busy: true, failed: false, status: '正在检查并同步…');
    try {
      await prepareLocal?.call();
      if (!_valid(epoch, user)) return;
      // A file restore removes the binding. Do not publish restored data using
      // a baseline retained in memory by this controller.
      if (!resolveLocal && await database.loadSetting('cloud_binding') == null) {
        _baselineRevision = null;
        _baselineDigest = null;
        state = state.copyWith(enabled: false, needsChoice: true);
      }
      final capturedGeneration = _generation;
      final snapshot = await _local();
      final digest = snapshotDigest(snapshot);
      state = state.copyWith(pendingLocal: _baselineDigest != null && digest != _baselineDigest);
      final remote = await _remoteMetadata(user);
      if (!_valid(epoch, user)) return;
      final decision = decideSync(localDigest: digest,
        baselineDigest: _baselineDigest, baselineRevision: _baselineRevision,
        remoteDigest: remote?['digest'] as String?,
        remoteRevision: (remote?['revision'] as num?)?.toInt());
      if (resolveLocal || decision == SyncDecision.upload) {
        final saved = await client!.rpc('save_korean_memo_snapshot', params: {
          'p_expected_revision': remote?['revision'] ?? 0,
          'p_digest': digest, 'p_payload': snapshot,
        }).timeout(const Duration(seconds: 30));
        if (!_valid(epoch, user)) return;
        await _remember(Map<String, dynamic>.from(saved as Map),
          enable: resolveLocal ? true : null, capturedGeneration: capturedGeneration);
      } else if (decision == SyncDecision.download) {
        if (automatic) {
          state = state.copyWith(hasRemote: true, needsChoice: true, cloudChanged: true,
            status: '云端有新进度，请点“现在同步”接续；本机数据尚未替换');
        } else {
          await _download(user, epoch, digest);
        }
      } else if (decision == SyncDecision.unchanged) {
        await _remember(remote!, capturedGeneration: capturedGeneration);
      } else {
        state = state.copyWith(hasRemote: remote != null, needsChoice: true, cloudChanged: false,
          status: remote == null ? '请先上传本机数据'
          : '本机和云端进度不同，请选择保留哪份数据');
      }
    } catch (error) {
      if (_valid(epoch, user)) _showError(error);
    } finally {
      if (_valid(epoch, user)) {
        state = state.copyWith(busy: false);
        _queueAutoSave();
      }
    }
  }

  Future<void> restoreCloud() async {
    if (state.busy || state.userId == null) return;
    final user = state.userId!, epoch = _epoch;
    _autoSaveTimer?.cancel();
    state = state.copyWith(busy: true, failed: false, status: '正在恢复云端进度…');
    try {
      await prepareLocal?.call();
      if (!_valid(epoch, user)) return;
      await _download(user, epoch, snapshotDigest(await _local()), enable: true);
    } catch (error) {
      if (_valid(epoch, user)) _showError(error);
    } finally {
      if (_valid(epoch, user)) state = state.copyWith(busy: false);
    }
  }

  Future<void> _download(String user, int epoch, String initialDigest,
      {bool? enable}) async {
    final remote = await client!.from('korean_memo_snapshots')
      .select().eq('user_id', user).maybeSingle().timeout(const Duration(seconds: 30));
    if (!_valid(epoch, user)) return;
    if (remote == null) throw const FormatException('云端还没有学习数据');
    final data = portableSnapshot(Map<String, Object?>.from(remote['payload'] as Map));
    if (snapshotDigest(data) != remote['digest']) {
      throw const FormatException('云端数据校验失败，请保留本机数据');
    }
    // The user may keep studying while a slow network request is in flight.
    // Compare and restore under one DB transaction, so new work is never lost.
    _restoring = true;
    try { await database.transaction(() async {
      if (!_valid(epoch, user)) return;
      if (snapshotDigest(await _local()) != initialDigest) {
        throw const FormatException('下载期间本机数据有更新，请重新选择同步');
      }
      await database.restoreBackupSnapshot(data);
      await _remember(remote, enable: enable);
    }); } finally { _restoring = false; }
    if (_valid(epoch, user)) onRestore();
  }

  void _showError(Object error) {
    lastError = error;
    final conflict = error is PostgrestException && error.code == '40001';
    state = state.copyWith(needsChoice: conflict || state.needsChoice,
      failed: !conflict, cloudChanged: false,
      status: conflict ? '另一台设备刚更新了进度，请重新检查并选择'
      : error is FormatException ? error.message
      : '同步暂未完成，本机进度已保存；联网后可重试');
  }

  Future<String> authenticate(String email, String password, {bool register = false}) async {
    if (client == null) return '云服务初始化失败，请重新打开应用';
    if (state.busy) return '请等待当前操作完成';
    state = state.copyWith(busy: true);
    final epoch = _epoch;
    try {
      if (register) {
        final response = await client!.auth.signUp(email: email, password: password)
          .timeout(const Duration(seconds: 30));
        if (response.session == null) {
          _lastResend = DateTime.now(); _lastResendEmail = email.trim();
        }
        return response.session == null ? '请到邮箱确认注册，然后返回应用登录' : '注册成功';
      }
      await client!.auth.signInWithPassword(email: email, password: password)
        .timeout(const Duration(seconds: 30));
      return '登录成功';
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) return '邮箱或密码不正确';
      if (message.contains('email not confirmed')) return '请先到邮箱确认注册，再返回登录';
      if (message.contains('rate limit')) return '请求过于频繁，请稍后再试';
      return error.message;
    } catch (_) {
      return '暂时无法登录，请检查网络后重试';
    } finally {
      if (mounted && epoch == _epoch) state = state.copyWith(busy: false);
    }
  }

  Future<String> signOut() async {
    if (state.busy) return '请等待同步完成';
    try {
      await client?.auth.signOut(scope: SignOutScope.local);
      await _loadAccount();
      return '已退出，本机学习进度仍保留';
    } catch (_) {
      return '退出失败，请稍后重试';
    }
  }

  void _markLocalChange() {
    if (!mounted || _restoring) return;
    _generation++;
    if (state.userId == null || _baselineRevision == null) return;
    state = state.copyWith(pendingLocal: true);
    _queueAutoSave();
  }

  void _localWatchFailed(Object error) {
    lastError = error;
    if (mounted) {
      state = state.copyWith(failed: true, status: '无法检查本机同步状态，请重新打开应用');
    }
  }

  void _queueAutoSave() {
    if (!mounted || !_foreground || !state.enabled || state.busy ||
        state.needsChoice || state.failed || !state.pendingLocal) {
      return;
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(autoSaveDelay, () {
      if (mounted && _foreground && state.enabled && !state.needsChoice) {
        unawaited(sync(automatic: true));
      }
    });
  }

  Future<String> resendConfirmation(String email) async {
    final trimmed = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)) {
      return '请先输入注册时使用的邮箱';
    }
    if (client == null) return '云服务初始化失败，请重新打开应用';
    if (state.busy) return '请等待当前操作完成';
    if (_lastResendEmail == trimmed && _lastResend != null &&
        DateTime.now().difference(_lastResend!) < const Duration(seconds: 60)) {
      return '确认邮件刚刚发送，请检查垃圾邮件或稍后再试';
    }
    final epoch = _epoch;
    state = state.copyWith(busy: true);
    try {
      await client!.auth.resend(type: OtpType.signup, email: trimmed)
        .timeout(const Duration(seconds: 30));
      _lastResend = DateTime.now(); _lastResendEmail = trimmed;
      return '已请求重新发送确认邮件，请检查邮箱和垃圾邮件';
    } on AuthException catch (error) {
      return error.message.toLowerCase().contains('rate limit')
        ? '发送过于频繁，请稍后再试' : error.message;
    } catch (_) {
      return '发送未完成，请检查网络后重试';
    } finally {
      if (mounted && epoch == _epoch) state = state.copyWith(busy: false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    _timer?.cancel();
    _autoSaveTimer?.cancel();
    _auth?.cancel();
    _dataChanges?.cancel();
    _settingsChanges?.cancel();
    super.dispose();
  }
}

final cloudSyncProvider = StateNotifierProvider<CloudSyncController, CloudSyncState>((ref) {
  return CloudSyncController(ref.watch(databaseProvider), ref.watch(cloudClientProvider), () {
    ref.invalidate(appearanceProvider);
    ref.invalidate(readingProvider);
    ref.invalidate(checkinsProvider);
    ref.invalidate(sessionOptionsProvider);
    ref.invalidate(sessionProgressProvider);
    ref.invalidate(homeCountsProvider);
    ref.invalidate(studyBookCountsProvider);
    ref.invalidate(wordBooksProvider);
    ref.invalidate(studyControllerProvider);
    ref.invalidate(dailyPlanSettingsProvider);
    ref.invalidate(dailyPlanProgressProvider);
    ref.invalidate(studyRoundProgressProvider);
    ref.invalidate(libraryWordsProvider);
    ref.invalidate(recentStatisticsProvider);
  }, prepareLocal: () async { await ref.read(bundledWordSeedProvider.future); });
});
