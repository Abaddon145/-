import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/settings/data/cloud_backup_api.dart';
import 'package:korean_memo/features/settings/data/cloud_backup_service.dart';
import 'package:korean_memo/features/settings/data/cloud_secret_store.dart';
import 'package:korean_memo/features/settings/presentation/cloud_backup_page.dart';
import 'package:korean_memo/features/study/domain/providers.dart';

class MemorySecrets implements CloudSecretStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  const token = 'ghp_supersecretvalue';

  test('gist upload keeps the newest files and hides the token', () async {
    final requests = <http.Request>[];
    final api = CloudBackupApi(
      MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer $token');
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'id': 'gist1'}), 201);
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'files': {
                'korean-memo-backup-20261120T010000Z.json': {},
                'korean-memo-backup-20261121T010000Z.json': {},
                'korean-memo-backup-20261122T010000Z.json': {},
              },
            }),
            200,
          );
        }
        return http.Response('{"ok":true,"echo":"$token"}', 200);
      }),
      now: () => DateTime.utc(2026, 11, 23, 1),
    );
    expect(
      await api.uploadGist(token: token, gistId: null, body: '{}', keep: 5),
      'gist1',
    );
    await api.uploadGist(token: token, gistId: 'gist1', body: '{}', keep: 2);
    final patch = jsonDecode(requests.last.body) as Map;
    final files = patch['files'] as Map;
    expect(
      files.containsKey('korean-memo-backup-20261123T010000Z.json'),
      isTrue,
    );
    expect(files['korean-memo-backup-20261120T010000Z.json'], isNull);
    expect(files['korean-memo-backup-20261121T010000Z.json'], isNull);
    expect(requests.last.body.contains(token), isFalse);
  });

  test('a rejected response never returns the token', () async {
    final api = CloudBackupApi(
      MockClient((_) async => http.Response('denied $token please', 401)),
    );
    expect(
      () => api.uploadGist(token: token, gistId: null, body: '{}', keep: 5),
      throwsA(
        isA<CloudBackupException>().having(
          (error) => error.message,
          'message',
          isNot(contains(token)),
        ),
      ),
    );
    final leaking = CloudBackupApi(
      MockClient((_) async => http.Response('boom $token', 500)),
    );
    expect(
      () => leaking.uploadGist(
        token: token,
        gistId: 'gist1',
        body: '{}',
        keep: 5,
      ),
      throwsA(
        isA<CloudBackupException>().having(
          (error) => error.message,
          'message',
          allOf(contains('500'), isNot(contains(token))),
        ),
      ),
    );
  });

  test('webdav keeps the newest backups', () async {
    final deleted = <String>[];
    final api = CloudBackupApi(
      MockClient((request) async {
        if (request.method == 'PUT') return http.Response('', 201);
        if (request.method == 'DELETE') {
          deleted.add(request.url.path);
          return http.Response('', 204);
        }
        return http.Response('''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>https://dav.example/ciyi/</d:href></d:response>
  <d:response><d:href>https://dav.example/ciyi/korean-memo-backup-20261120T010000Z.json</d:href></d:response>
  <d:response><d:href>https://dav.example/ciyi/korean-memo-backup-20261121T010000Z.json</d:href></d:response>
  <d:response><d:href>https://dav.example/ciyi/korean-memo-backup-20261122T010000Z.json</d:href></d:response>
</d:multistatus>
''', 207);
      }),
      now: () => DateTime.utc(2026, 11, 23, 1),
    );
    await api.uploadWebDav(
      directory: parseWebDavDirectory('https://dav.example/ciyi'),
      user: 'learner',
      password: 'secret-pass',
      body: '{}',
      keep: 2,
    );
    expect(deleted, [
      '/ciyi/korean-memo-backup-20261120T010000Z.json',
      '/ciyi/korean-memo-backup-20261121T010000Z.json',
    ]);
    expect(
      () => parseWebDavDirectory('https://user:secret-pass@dav.example/ciyi'),
      throwsA(isA<CloudBackupException>()),
    );
  });

  test('backup files omit tokens and restore ignores them', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = MemorySecrets();
    final calls = <String>[];
    final api = CloudBackupApi(
      MockClient((request) async {
        calls.add(request.method);
        expect(request.body.contains(token), isFalse);
        expect(request.headers['Authorization'], 'Bearer $token');
        return http.Response(jsonEncode({'id': 'gist9'}), 201);
      }),
    );
    final service = CloudBackupService(db, secrets, api);
    await service.saveConfig(
      const CloudBackupConfig(kind: 'gist', keep: 5, everyHours: 24),
      githubToken: token,
    );
    await db.saveSetting('backup_cloud_github_token', token);
    await service.backup(manual: true);
    final snapshot = jsonEncode(await db.createBackupSnapshot());
    expect(snapshot.contains(token), isFalse);
    expect(await db.loadSetting('backup_cloud_gist_id'), 'gist9');
    expect(calls, ['POST']);

    final crafted = await db.createBackupSnapshot();
    final tables = crafted['tables'] as Map;
    (tables['app_settings'] as List).add({
      'key': 'backup_cloud_github_token',
      'value': token,
      'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    });
    await db.restoreBackupSnapshot(crafted.cast<String, dynamic>());
    expect(await db.loadSetting('backup_cloud_github_token'), isNull);
    expect(secrets.values[CloudSecretStore.github], token);
  });

  testWidgets('cloud backup page warns about the gist scope', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          cloudSecretStoreProvider.overrideWithValue(MemorySecrets()),
        ],
        child: const MaterialApp(home: CloudBackupPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('只勾选 gist'), findsOneWidget);
    expect(find.textContaining('不会写进备份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
