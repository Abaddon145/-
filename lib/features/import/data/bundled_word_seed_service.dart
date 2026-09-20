import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';

class BundledWordSeedService {
  const BundledWordSeedService();

  static const assetPath = 'assets/data/default_word_books.json';

  Future<BundledSeedResult> seed(AppDatabase database) async {
    final raw = await rootBundle.loadString(assetPath);
    final books = decode(raw);
    var inserted = 0;
    var reused = 0;
    var importedBooks = 0;
    var existingBooks = 0;

    for (final book in books) {
      final result = await database.importWordBookIfMissing(
        name: book.name,
        sourceFileName: book.sourceFileName,
        drafts: book.drafts,
      );
      if (result == null) {
        existingBooks++;
      } else {
        importedBooks++;
        inserted += result.inserted;
        reused += result.reused;
      }
    }

    return BundledSeedResult(
      importedBooks: importedBooks,
      existingBooks: existingBooks,
      inserted: inserted,
      reused: reused,
      bundledEntries: books.fold(0, (sum, book) => sum + book.drafts.length),
    );
  }

  List<BundledWordBook> decode(String raw) {
    final payload = jsonDecode(raw);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('内置词库格式无效。');
    }
    final rawBooks = payload['books'];
    if (rawBooks is! List) {
      throw const FormatException('内置词库缺少 books。');
    }

    return rawBooks.map((rawBook) {
      if (rawBook is! Map<String, dynamic>) {
        throw const FormatException('内置词库包含无效分组。');
      }
      final name = rawBook['name']?.toString().trim() ?? '';
      final sourceFileName =
          rawBook['sourceFileName']?.toString().trim() ?? '';
      final rawWords = rawBook['words'];
      if (name.isEmpty || sourceFileName.isEmpty || rawWords is! List) {
        throw const FormatException('内置词库分组信息不完整。');
      }
      final drafts = rawWords.map((rawWord) {
        if (rawWord is! Map<String, dynamic>) {
          throw const FormatException('内置词库包含无效词条。');
        }
        final korean = rawWord['korean']?.toString().trim() ?? '';
        final meaningZh = rawWord['meaningZh']?.toString().trim() ?? '';
        if (korean.isEmpty || meaningZh.isEmpty) {
          throw const FormatException('内置词库包含空白韩语或中文释义。');
        }
        return WordDraft(korean: korean, meaningZh: meaningZh);
      }).toList(growable: false);
      return BundledWordBook(
        name: name,
        sourceFileName: sourceFileName,
        drafts: drafts,
      );
    }).toList(growable: false);
  }
}

class BundledWordBook {
  const BundledWordBook({
    required this.name,
    required this.sourceFileName,
    required this.drafts,
  });

  final String name;
  final String sourceFileName;
  final List<WordDraft> drafts;
}

class BundledSeedResult {
  const BundledSeedResult({
    required this.importedBooks,
    required this.existingBooks,
    required this.inserted,
    required this.reused,
    required this.bundledEntries,
  });

  final int importedBooks;
  final int existingBooks;
  final int inserted;
  final int reused;
  final int bundledEntries;
}
