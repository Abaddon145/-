import '../../../core/database/app_database.dart';

class MasteryCount {
  const MasteryCount({
    required this.language,
    this.fresh = 0,
    this.week = 0,
    this.month = 0,
    this.steady = 0,
  });

  final String language;
  final int fresh;
  final int week;
  final int month;
  final int steady;

  int get total => fresh + week + month + steady;
}

class LanguageComparison {
  const LanguageComparison({required this.mastery, required this.days});

  final Map<String, MasteryCount> mastery;
  final Map<String, List<DailyStatisticsSummary>> days;
}

extension LanguageComparisonQuery on AppDatabase {
  Future<Map<String, MasteryCount>> masteryByLanguage() async {
    final rows = await customSelect(
      'SELECT language, '
      'SUM(CASE WHEN stability < 1 THEN 1 ELSE 0 END) AS fresh, '
      'SUM(CASE WHEN stability >= 1 AND stability < 7 THEN 1 ELSE 0 END) AS week, '
      'SUM(CASE WHEN stability >= 7 AND stability < 30 THEN 1 ELSE 0 END) AS month, '
      'SUM(CASE WHEN stability >= 30 THEN 1 ELSE 0 END) AS steady '
      'FROM study_cards GROUP BY language',
    ).get();
    final counts = {
      for (final language in const ['ko', 'en'])
        language: MasteryCount(language: language),
    };
    for (final row in rows) {
      final language = row.data['language']?.toString() ?? '';
      if (language != 'ko' && language != 'en') continue;
      counts[language] = MasteryCount(
        language: language,
        fresh: _cell(row.data, 'fresh'),
        week: _cell(row.data, 'week'),
        month: _cell(row.data, 'month'),
        steady: _cell(row.data, 'steady'),
      );
    }
    return counts;
  }
}

int _cell(Map<dynamic, dynamic> data, String name) {
  final value = data[name];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
