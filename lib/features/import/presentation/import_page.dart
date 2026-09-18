import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../study/domain/providers.dart';
import '../data/excel_import_service.dart';
import '../domain/import_models.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _service = ExcelImportService();
  ParsedWorkbook? _preview;
  String? _fileName;
  Object? _error;
  bool _busy = false;

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('无法读取所选文件。');
      }
      final preview = _service.parseFirstSheet(Uint8List.fromList(bytes));
      setState(() {
        _preview = preview;
        _fileName = file.name;
      });
    } catch (error) {
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    final fileName = _fileName;
    if (preview == null || fileName == null || _busy) return;
    setState(() => _busy = true);
    try {
      final database = ref.read(databaseProvider);
      final bookId = await database.createWordBook(
        name: preview.sheetName,
        sourceFileName: fileName,
      );
      final result = await database.importWords(
        wordBookId: bookId,
        drafts: preview.drafts,
        source: fileName,
      );
      ref.invalidate(homeCountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入完成：新增 ${result.inserted}，复用 ${result.reused}'),
        ),
      );
      context.go('/');
    } catch (error) {
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('导入 Excel 词库')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '至少需要“韩语单词”和“中文释义”两列。当前版本会读取第一个 Sheet 并自动匹配常见表头。',
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(_fileName ?? '选择 .xlsx 文件'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: 24),
              Text('Sheet：${preview.sheetName}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '有效 ${preview.drafts.length} 条 · 异常 ${preview.invalidRows} 条 · '
                '识别 ${preview.mapping.length} 个字段',
              ),
              const SizedBox(height: 16),
              ...preview.drafts.take(5).map(
                    (word) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(word.korean),
                      subtitle: Text(word.meaningZh),
                    ),
                  ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy || preview.drafts.isEmpty ? null : _import,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('确认导入'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
