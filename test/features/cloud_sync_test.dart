import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/sync/domain/sync_snapshot.dart';

void main() {
  test('new device and simultaneous edits require an explicit choice', () {
    expect(decideSync(localDigest: 'a', baselineDigest: null,
      baselineRevision: null, remoteDigest: 'b', remoteRevision: 1), SyncDecision.conflict);
    expect(decideSync(localDigest: 'a', baselineDigest: null,
      baselineRevision: null, remoteDigest: null, remoteRevision: null), SyncDecision.conflict);
    expect(decideSync(localDigest: 'local-change', baselineDigest: 'old',
      baselineRevision: 1, remoteDigest: 'remote-change', remoteRevision: 2), SyncDecision.conflict);
  });

  test('one-sided changes upload or download without overwriting new work', () {
    expect(decideSync(localDigest: 'new', baselineDigest: 'old',
      baselineRevision: 1, remoteDigest: 'old', remoteRevision: 1), SyncDecision.upload);
    expect(decideSync(localDigest: 'old', baselineDigest: 'old',
      baselineRevision: 1, remoteDigest: 'new', remoteRevision: 2), SyncDecision.download);
    expect(decideSync(localDigest: 'same', baselineDigest: 'old',
      baselineRevision: 1, remoteDigest: 'same', remoteRevision: 3), SyncDecision.unchanged);
  });

  test('digest survives reordered SQL rows, JSON keys and snapshot timestamps', () {
    final a = {'createdAt': 'first', 'tables': {'words': [
      {'id': 2, 'korean': '바다'}, {'id': 1, 'korean': '하늘'}]}};
    final b = {'createdAt': 'second', 'tables': {'words': [
      {'korean': '하늘', 'id': 1}, {'korean': '바다', 'id': 2}]}};
    expect(snapshotDigest(a), snapshotDigest(b));
    b['tables'] = {'words': [{'id': 1, 'korean': '다른'}]};
    expect(snapshotDigest(a), isNot(snapshotDigest(b)));
  });

  test('cloud markers and session undo never travel with learning data', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.saveSetting('cloud_binding', '{"userId":"device-only"}');
    await db.saveSetting('last_review_undo', 'device-undo');
    await db.saveSetting('selected_learning_session', 'device-round');
    await db.saveSetting('checkin:2026-10-13', '1');
    await db.saveSetting('appearance_style', 'ink');
    final raw = await db.createBackupSnapshot();
    expect(((raw['tables'] as Map)['app_settings'] as List)
      .any((row) => (row as Map)['key'] == 'cloud_binding'), isFalse);
    final snapshot = portableSnapshot(raw);
    final keys = ((snapshot['tables'] as Map)['app_settings'] as List)
      .map((row) => (row as Map)['key']).toSet();
    expect(keys, containsAll(['checkin:2026-10-13', 'appearance_style']));
    expect(keys, isNot(contains('last_review_undo')));
    expect(keys, isNot(contains('selected_learning_session')));
    await db.restoreBackupSnapshot(snapshot);
    expect(await db.loadSetting('cloud_binding'), isNull);
    expect(await db.loadSetting('checkin:2026-10-13'), '1');
    expect(await db.recoverPreviousRestore(), isTrue);
  });
}
