import 'dart:convert';

import 'package:crypto/crypto.dart';

// Device state and undo records must not travel in backups or cloud snapshots.
bool portableSetting(String key) =>
    !key.startsWith('cloud_') &&
    key != 'last_review_undo' &&
    key != 'last_backup_at' &&
    key != 'selected_learning_session';

Map<String, dynamic> portableSnapshot(Map<String, Object?> snapshot) {
  final result = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  final tables = result['tables'] as Map<String, dynamic>;
  tables['app_settings'] = (tables['app_settings'] as List)
      .where((row) => portableSetting((row as Map)['key'] as String))
      .toList();
  return result;
}

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

// Ignore snapshot creation time and row ordering, but include every saved value.
String snapshotDigest(Map<String, dynamic> snapshot) {
  final tables = snapshot['tables'] as Map;
  final canonical = <String, dynamic>{};
  for (final entry in tables.entries) {
    final rows = (entry.value as List)
        .map((row) => jsonEncode(_canonical(row)))
        .toList()..sort();
    canonical[entry.key as String] = rows;
  }
  return sha256.convert(utf8.encode(jsonEncode(_canonical(canonical)))).toString();
}

enum SyncDecision { upload, download, unchanged, conflict }

SyncDecision decideSync({
  required String localDigest,
  required String? baselineDigest,
  required int? baselineRevision,
  required String? remoteDigest,
  required int? remoteRevision,
}) {
  if (remoteDigest == null || remoteRevision == null) {
    return baselineRevision == null ? SyncDecision.conflict : SyncDecision.upload;
  }
  if (localDigest == remoteDigest) return SyncDecision.unchanged;
  if (baselineDigest == null || baselineRevision == null) {
    return SyncDecision.conflict;
  }
  if (remoteRevision == baselineRevision) return SyncDecision.upload;
  if (localDigest == baselineDigest) return SyncDecision.download;
  return SyncDecision.conflict;
}
