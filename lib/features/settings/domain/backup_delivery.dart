import '../../../core/database/app_database.dart';

enum BackupDelivery { written, shared, acknowledged, cancelled, downloadOnly }

bool recordsBackupExport(BackupDelivery delivery) =>
    delivery == BackupDelivery.written ||
    delivery == BackupDelivery.shared ||
    delivery == BackupDelivery.acknowledged;

/// Writes the export timestamp only after a file was actually saved or the
/// user confirmed that the downloaded file is on disk.
Future<bool> recordBackupExport(
  AppDatabase database,
  BackupDelivery delivery,
  DateTime now,
) async {
  if (!recordsBackupExport(delivery)) return false;
  await database.saveSetting('last_backup_at', now.toUtc().toIso8601String());
  await database.saveSetting('backup_snoozed_until', null);
  return true;
}
