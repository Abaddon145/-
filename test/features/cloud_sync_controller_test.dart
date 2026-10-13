import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/sync/domain/sync_snapshot.dart';
import 'package:korean_memo/features/sync/presentation/cloud_sync_controller.dart';

void main() {
  const uid = 'd47f4b01-5d18-4bd2-9826-9b9e80981c23';
  late AppDatabase db;
  late SupabaseClient client;
  late CloudSyncController controller;
  late Map<String, dynamic> remote;
  int writes = 0;
  Completer<void>? downloadGate;
  Completer<void>? downloadStarted;
  Completer<void>? uploadGate;
  Completer<void>? uploadStarted;
  bool unavailable = false;
  int confirmationRequests = 0;

  http.Response response(Object data, {int status = 200, required http.Request request}) =>
    http.Response(jsonEncode(data), status, request: request,
      headers: {'content-type': 'application/json'});

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 50 && controller.state.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.state.busy, isFalse);
  }

  setUp(() async {
    writes = 0;
    downloadGate = null;
    downloadStarted = null;
    uploadGate = null;
    uploadStarted = null;
    unavailable = false;
    confirmationRequests = 0;
    db = AppDatabase(NativeDatabase.memory());
    await db.saveSetting('test_note', 'local');
    final snapshot = portableSnapshot(await db.createBackupSnapshot());
    remote = {'user_id': uid, 'revision': 3, 'digest': snapshotDigest(snapshot),
      'updated_at': DateTime.now().toUtc().toIso8601String(), 'payload': snapshot};
    final transport = MockClient((request) async {
      if (request.url.path == '/auth/v1/resend') {
        confirmationRequests++;
        return response({'message_id': 'test-confirmation'}, request: request);
      }
      if (request.url.path == '/auth/v1/token') {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final jwt = '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
          '${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': now + 3600, 'iat': now, 'aud': 'authenticated'})))}.test';
        return response({'access_token': jwt, 'refresh_token': 'test-refresh',
          'token_type': 'bearer', 'expires_in': 3600, 'expires_at': now + 3600,
          'user': {'id': uid, 'email': 'test@example.invalid', 'aud': 'authenticated',
            'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{},
            'created_at': DateTime.now().toUtc().toIso8601String()}}, request: request);
      }
      if (request.url.path.endsWith('/rpc/save_korean_memo_snapshot')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (uploadStarted?.isCompleted == false) uploadStarted!.complete();
        await uploadGate?.future;
        if (body['p_expected_revision'] != remote['revision']) {
          return response({'code': '40001', 'message': 'SYNC_CONFLICT'}, status: 409, request: request);
        }
        writes++;
        remote = {...remote, 'revision': (remote['revision'] as int) + 1,
          'digest': body['p_digest'], 'payload': body['p_payload']};
        return response({'revision': remote['revision'], 'digest': remote['digest'],
          'updated_at': remote['updated_at']}, request: request);
      }
      if (request.url.path.endsWith('/korean_memo_snapshots')) {
        if (unavailable) {
          return response({'code': 'TEST_UNAVAILABLE', 'message': 'connection unavailable'},
            status: 400, request: request);
        }
        if (request.url.queryParameters['select'] == '*') {
          downloadStarted?.complete();
          await downloadGate?.future;
        }
        // maybeSingle uses a normal JSON array for GET and checks its length.
        return response([remote], request: request);
      }
      return response({'message': 'unexpected request'}, status: 500, request: request);
    });
    client = SupabaseClient('https://example.invalid', 'test-publishable', httpClient: transport);
    controller = CloudSyncController(db, client, () {});
  });

  tearDown(() async {
    controller.dispose();
    await client.dispose();
    await db.close();
  });

  test('login never uploads; linked device uploads only its own changes', () async {
    await controller.authenticate('test@example.invalid', 'password');
    await settle();
    expect(writes, 0);
    expect(controller.state.enabled, isFalse);
    expect(controller.state.needsChoice, isTrue, reason: '${controller.lastError}');
    expect(await db.loadSetting('test_note'), 'local');
    await controller.sync(resolveLocal: true);
    expect(writes, 1);
    expect(controller.state.enabled, isTrue);
    await db.saveSetting('test_note', 'local-change');
    await controller.sync(automatic: true);
    expect(writes, 2);
    remote = {...remote, 'revision': 6, 'digest': 'remote-change'};
    await db.saveSetting('test_note', 'another-local-change');
    await controller.sync(automatic: true);
    expect(writes, 2);
    expect(controller.state.needsChoice, isTrue);
    expect(await db.loadSetting('test_note'), 'another-local-change');
  });

  test('slow download refuses to overwrite work saved during the request', () async {
    await controller.authenticate('test@example.invalid', 'password');
    await settle();
    downloadGate = Completer<void>();
    downloadStarted = Completer<void>();
    final operation = controller.restoreCloud();
    await downloadStarted!.future;
    await db.saveSetting('test_note', 'saved-during-download');
    downloadGate!.complete();
    await operation;
    expect(await db.loadSetting('test_note'), 'saved-during-download');
    expect(controller.state.status, contains('下载期间'), reason: '${controller.lastError}');
    expect(controller.state.enabled, isFalse);
    expect(writes, 0);
  });

  test('restoring a file pauses stale in-memory binding before any upload', () async {
    await controller.authenticate('test@example.invalid', 'password');
    await settle();
    await controller.sync(resolveLocal: true);
    await controller.pauseForLocalRestore();
    await db.saveSetting('test_note', 'restored-progress');
    await controller.sync(automatic: true);
    expect(controller.state.enabled, isFalse);
    expect(controller.state.needsChoice, isTrue);
    expect(writes, 1, reason: '${controller.lastError}');
  });

  test('records saved during upload remain pending until the next snapshot', () async {
    await controller.authenticate('test@example.invalid', 'password');
    await settle();
    await controller.sync(resolveLocal: true);
    await db.saveSetting('test_note', 'captured-for-upload');
    uploadGate = Completer<void>(); uploadStarted = Completer<void>();
    final operation = controller.sync();
    await uploadStarted!.future;
    await db.saveSetting('test_note', 'saved-during-upload');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    uploadGate!.complete();
    await operation;
    expect(controller.state.pendingLocal, isTrue);
    expect(controller.state.label, '本机记录待保存');
    final rows = ((remote['payload'] as Map)['tables'] as Map)['app_settings'] as List;
    expect(rows.singleWhere((row) => (row as Map)['key'] == 'test_note')['value'], 'captured-for-upload');
    uploadGate = null; uploadStarted = null;
    await controller.sync();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.pendingLocal, isFalse);
    expect(controller.state.label, '已与云端一致');
  });

  test('device-only metadata never causes pending-save notifications', () async {
    await controller.authenticate('test@example.invalid', 'password');
    await settle();
    await controller.sync(resolveLocal: true);
    await db.saveSetting('last_backup_at', 'device-backup');
    await db.saveSetting('last_review_undo', 'device-undo');
    await db.saveSetting('cloud_last_check', 'device-clock');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.pendingLocal, isFalse);
    expect(writes, 1);
    await db.saveSetting('checkin:2026-10-13', '1');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.pendingLocal, isTrue);
  });

  test('failed sync keeps local records pending and can recover without a new choice', () async {
    await controller.authenticate('test@example.invalid', 'password');
    await settle();
    await controller.sync(resolveLocal: true);
    await db.saveSetting('test_note', 'offline-record');
    unavailable = true;
    await controller.sync();
    expect(controller.state.pendingLocal, isTrue);
    expect(controller.state.failed, isTrue);
    expect(controller.state.label, '同步待重试');
    expect(await db.loadSetting('test_note'), 'offline-record');
    expect(writes, 1);
    unavailable = false;
    await controller.sync();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.failed, isFalse);
    expect(controller.state.pendingLocal, isFalse);
    expect(writes, 2);
  });

  test('confirmation resend validates email and prevents duplicate sends', () async {
    expect(await controller.resendConfirmation('invalid-email'), contains('输入'));
    expect(confirmationRequests, 0);
    expect(await controller.resendConfirmation('test@example.invalid'), contains('重新发送'));
    expect(confirmationRequests, 1);
    expect(await controller.resendConfirmation('test@example.invalid'), contains('稍后'));
    expect(confirmationRequests, 1);
    expect(controller.state.userId, isNull);
  });
}
