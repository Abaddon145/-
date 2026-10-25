import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';

class BackupStatus {
  const BackupStatus({this.lastExport, this.snoozedUntil, this.enabled = true});
  final DateTime? lastExport, snoozedUntil;
  final bool enabled;
  static DateTime? parse(String? value) =>
      DateTime.tryParse(value ?? '')?.toUtc();
  bool isDue(DateTime now) =>
      enabled &&
      !(snoozedUntil?.isAfter(now.toUtc()) ?? false) &&
      (lastExport == null ||
          now.toUtc().difference(lastExport!) >= const Duration(days: 7));
  String get lastExportLabel {
    final date = lastExport?.toLocal();
    return date == null
        ? '还没有导出备份'
        : '上次导出：${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

final backupStatusProvider = FutureProvider.autoDispose<BackupStatus>((
  ref,
) async {
  ref.watch(localDayProvider);
  final db = ref.watch(databaseProvider);
  final values = await Future.wait([
    db.loadSetting('last_backup_at'),
    db.loadSetting('backup_snoozed_until'),
    db.loadSetting('backup_reminders_enabled'),
  ]);
  return BackupStatus(
    lastExport: BackupStatus.parse(values[0]),
    snoozedUntil: BackupStatus.parse(values[1]),
    enabled: values[2] != 'false',
  );
});
