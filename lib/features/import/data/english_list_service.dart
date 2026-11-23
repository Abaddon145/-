import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';

class EnglishBuiltInList {
  const EnglishBuiltInList(this.id, this.title, this.asset);
  final String id;
  final String title;
  final String asset;
}

const englishBuiltInLists = [
  EnglishBuiltInList('cet4', 'CET-4', 'assets/data/english/cet4.json'),
  EnglishBuiltInList('cet6', 'CET-6', 'assets/data/english/cet6.json'),
  EnglishBuiltInList('ky', '考研', 'assets/data/english/ky.json'),
  EnglishBuiltInList('ielts', 'IELTS', 'assets/data/english/ielts.json'),
];

List<WordDraft> draftsFromEnglishList(String raw) {
  final data = jsonDecode(raw);
  if (data is! Map || data['words'] is! List) {
    throw const FormatException('内置词表格式无效');
  }
  return [
    for (final row in data['words'] as List)
      if (row is Map &&
          (row['w'] ?? '').toString().trim().isNotEmpty &&
          (row['z'] ?? '').toString().trim().isNotEmpty)
        WordDraft(
          korean: row['w'].toString().trim(),
          meaningZh: row['z'].toString().trim(),
        ),
  ];
}

Future<List<WordDraft>> loadEnglishBuiltInList(EnglishBuiltInList list) {
  return rootBundle.loadString(list.asset).then(draftsFromEnglishList);
}
