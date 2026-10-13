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

  http.Response response(Object data, {int status = 200}) =>
    http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json'});

  Future<void> settle() async {
    for (var i = 0; i < 50 && controller.state.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.state.busy, isFalse);
  }

  setUp(() async {
    writes = 0;
    downloadGate = null;
    downloadStarted = null;
    db = AppDatabase(NativeDatabase.memory());
    await db.saveSetting('test_note', 'local');
    final snapshot = portableSnapshot(await db.createBackupSnapshot());
    remote = {'user_id': uid, 'revision': 3, 'digest': snapshotDigest(snapshot),
      'updated_at': DateTime.now().toUtc().toIso8601String(), 'payload': snapshot};
    final transport = MockClient((request) async {
      if (request.url.path == '/auth/v1/token') {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final jwt = '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
          '${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': now + 3600, 'iat': now, 'aud': 'authenticated'})))}.test';
        return response({'access_token': jwt, 'refresh_token': 'test-refresh',
          'token_type': 'bearer', 'expires_in': 3600, 'expires_at': now + 3600,
          'user': {'id': uid, 'email': 'test@example.invalid', 'aud': 'authenticated',
            'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{},
            'created_at': DateTime.now().toUtc().toIso8601String()}});
      }
      if (request.url.path.endsWith('/rpc/save_korean_memo_snapshot')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['p_expected_revision'] != remote['revision']) {
          return response({'code': '40001', 'message': 'SYNC_CONFLICT'}, status: 409);
        }
        writes++;
        remote = {...remote, 'revision': (remote['revision'] as int) + 1,
          'digest': body['p_digest'], 'payload': body['p_payload']};
        return response({'revision': remote['revision'], 'digest': remote['digest'],
          'updated_at': remote['updated_at']});
      }
      if (request.url.path.endsWith('/korean_memo_snapshots')) {
        if (request.url.queryParameters['select'] == '*') {
          downloadStarted?.complete();
          await downloadGate?.future;
        }
        return response(remote);
      }
      return response({'message': 'unexpected request'}, status: 500);
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
    expect(controller.state.needsChoice, isTrue);
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
    expect(controller.state.status, contains('下载期间'));
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
    expect(writes, 1);
  });
}
