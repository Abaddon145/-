import '../../../core/database/app_database.dart';

const aiDirectRequestPrefix = 'ai_direct_requests:';

Future<int> loadTodayDirectRequests(AppDatabase database, DateTime now) async {
  final value = await database.loadSetting('$aiDirectRequestPrefix${dayKey(now)}');
  return int.tryParse(value ?? '') ?? 0;
}

Future<void> recordDirectAiRequest(AppDatabase database) async {
  final now = DateTime.now();
  final key = '$aiDirectRequestPrefix${dayKey(now)}';
  final next = (int.tryParse(await database.loadSetting(key) ?? '') ?? 0) + 1;
  await database.saveSetting(key, '$next');
}
