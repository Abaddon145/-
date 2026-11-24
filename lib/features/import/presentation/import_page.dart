import 'dart:typed_data';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../study/domain/providers.dart';
import '../../study/presentation/study_controller.dart';
import '../../library/domain/providers.dart';
import '../../../core/database/app_database.dart';
import '../data/csv_import_service.dart';
import '../data/english_list_service.dart';
import '../data/excel_import_service.dart';
import '../domain/import_models.dart';
import '../../atlas/data/atlas_remote.dart';
import '../../atlas/domain/atlas_models.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _service = ExcelImportService();
  ParsedWorkbook? _preview;
  Uint8List? _bytes;
  List<String> _sheets = [], _headers = [];
  Map<ImportField, int> _mapping = {};
  String? _sheet, _fileName;
  Object? _error;
  bool _busy = false, _all = false, _enrich = true, _parsing = false;
  String _stage = '';
  int _duplicates = 0, _version = 0;
  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _bytes = null;
      _fileName = null;
      _sheets = [];
      _headers = [];
      _mapping = {};
      _stage = '请选择文件';
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null || !mounted) return;
      if (!file.name.toLowerCase().endsWith('.xlsx')) {
        throw const FormatException(
          '请选择.xlsx格式；.xls或.csv请先在Excel/WPS中另存为.xlsx',
        );
      }
      setState(() {
        _stage = '正在读取文件…';
        _bytes = null;
      });
      final data = Uint8List.fromList(
        await file.readAsBytes().timeout(const Duration(seconds: 30)),
      );
      if (!mounted) return;
      setState(() => _stage = '正在解析工作表…');
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      if (data.length > 20 * 1024 * 1024) {
        throw const FormatException('Excel 文件过大，请分批导入（最大20MB）');
      }
      _bytes = data;
      _fileName = file.name;
      _sheets = _service.sheetNames(data);
      _sheet = _sheets.first;
      _all = false;
      _headers = _service.sheetHeaders(data, _sheet!);
      _mapping = _service.guessMapping(_headers);
      await _parse();
    } catch (e) {
      _bytes = null;
      if (mounted) {
        setState(
          () => _error = e is TimeoutException ? '读取文件超时，请先将文件下载到本机再重试' : e,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = '';
        });
      }
    }
  }

  Future<void> _parse() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final version = ++_version;
    setState(() {
      _parsing = true;
      _preview = null;
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted || version != _version) return;
    try {
      final preview = _service.parseFirstSheet(
        bytes,
        sheetName: _sheet,
        mappingOverride: _mapping,
        allSheets: _all,
      );
      await ref.read(bundledWordSeedProvider.future);
      if (!mounted || version != _version) return;
      final words = await ref
          .read(databaseProvider)
          .select(ref.read(databaseProvider).words)
          .get();
      final existing = words
          .map((w) => '${w.normalizedHeadword}\u0000${w.normalizedBaseForm}')
          .toSet();
      var duplicates = 0;
      for (final draft in preview.drafts) {
        final key =
            '${draft.normalizedKorean}\u0000${draft.normalizedBaseForm}';
        if (!existing.add(key)) duplicates++;
      }
      if (mounted && version == _version) {
        setState(() {
          _preview = preview;
          _duplicates = duplicates;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && version == _version) {
        setState(() {
          _error = e;
          _preview = null;
        });
      }
    } finally {
      if (mounted && version == _version) {
        setState(() => _parsing = false);
      }
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || _busy || _parsing) return;
    setState(() {
      _busy = true;
      _stage = '正在保存到统一词库…';
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await db.transaction(() async {
        final book = await db.createWordBook(
          name: preview.sheetName,
          sourceFileName: _fileName!,
        );
        return db.importWords(
          wordBookId: book,
          drafts: preview.drafts,
          source: _fileName!,
          enrichExisting: _enrich,
        );
      });
      ref.invalidate(studyBookCountsProvider);
      ref.invalidate(sessionProgressProvider);
      ref.invalidate(studyRoundProgressProvider);
      ref.invalidate(homeCountsProvider);
      ref.invalidate(wordBooksProvider);
      ref.invalidate(libraryWordsProvider);
      ref.invalidate(studyControllerProvider);
      ref.invalidate(dailyPlanProgressProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('统一词库新增 ${result.inserted} · 复用 ${result.reused}'),
          ),
        );
        context.go('/library');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(activeLanguageProvider) == 'en') {
      return const _EnglishCsvImportPage();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('导入韩语词库')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '请选择 .xlsx。英文列会和韩语列一起写入韩语词库，不会进入英语空间。只有中文的行跳过。不会覆盖原有学习进度。',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy || _parsing ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName ?? '选择.xlsx文件'),
            ),
            if (_busy || _parsing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              Text(_parsing ? '正在生成导入预览…' : _stage),
            ],
            if (_bytes != null) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('$_fileName-$_sheet'),
                isExpanded: true,
                initialValue: _sheet,
                decoration: const InputDecoration(labelText: '工作表'),
                items: [
                  for (final name in _sheets)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: _busy || _parsing
                    ? null
                    : (v) {
                        _sheet = v;
                        _headers = _service.sheetHeaders(_bytes!, v!);
                        _mapping = _service.guessMapping(_headers);
                        _parse();
                      },
              ),
              SwitchListTile(
                title: const Text('读取全部自动识别的工作表'),
                subtitle: const Text('无法识别的工作表计入跳过行；自定义列映射请逐表导入'),
                value: _all,
                onChanged: _busy || _parsing
                    ? null
                    : (v) {
                        setState(() => _all = v);
                        _parse();
                      },
              ),
              if (!_all)
                for (final field in const [
                  ImportField.korean,
                  ImportField.english,
                  ImportField.meaningZh,
                  ImportField.partOfSpeech,
                  ImportField.exampleKo,
                  ImportField.tags,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      key: ValueKey('$_sheet-${field.name}-${_mapping[field]}'),
                      initialValue: _mapping[field] ?? -1,
                      decoration: InputDecoration(labelText: field.label),
                      items: [
                        const DropdownMenuItem(value: -1, child: Text('未指定')),
                        for (var i = 0; i < _headers.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${i + 1} · ${_headers[i]}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy || _parsing
                          ? null
                          : (v) {
                              if (v == -1) {
                                _mapping.remove(field);
                              } else {
                                _mapping[field] = v!;
                              }
                              _parse();
                            },
                    ),
                  ),
              SwitchListTile(
                title: const Text('补齐重复词的缺失字段'),
                subtitle: const Text('保留已有释义、例句、词性和学习状态'),
                value: _enrich,
                onChanged: _busy || _parsing
                    ? null
                    : (v) => setState(() => _enrich = v),
              ),
            ],
            if (_error != null)
              Text(
                '$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Text(
                '有效 ${_preview!.drafts.length} · 重复 $_duplicates · 跳过/异常 ${_preview!.invalidRows}',
              ),
              for (final word in _preview!.drafts.take(8))
                ListTile(
                  title: Text(word.korean),
                  subtitle: Text('${word.meaningZh} · ${word.tags ?? ''}'),
                ),
              FilledButton(
                onPressed: _busy || _parsing || _preview!.drafts.isEmpty
                    ? null
                    : _import,
                child: Text(_busy ? '正在导入…' : '确认合并到统一词库'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EnglishCsvImportPage extends ConsumerStatefulWidget {
  const _EnglishCsvImportPage();
  @override
  ConsumerState<_EnglishCsvImportPage> createState() =>
      _EnglishCsvImportPageState();
}

class _EnglishCsvImportPageState extends ConsumerState<_EnglishCsvImportPage> {
  final _service = CsvImportService();
  CsvImportResult? _preview;
  String? _fileName, _error;
  bool _busy = false;
  String _stage = '';

  Future<void> _importBuiltIn(EnglishBuiltInList list) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final drafts = await loadEnglishBuiltInList(list);
      final db = ref.read(databaseProvider);
      final source = 'english-list://${list.id}';
      final result = await db.transaction(() async {
        final existing =
            await (db.select(db.wordBooks)
                  ..where((row) => row.sourceFileName.equals(source))
                  ..where((row) => row.language.equals('en')))
                .getSingleOrNull();
        final book =
            existing?.id ??
            await db.createWordBook(
              name: list.title,
              sourceFileName: source,
              language: 'en',
            );
        return db.importWords(
          wordBookId: book,
          drafts: drafts,
          source: source,
          language: 'en',
        );
      });
      ref.invalidate(homeCountsProvider);
      ref.invalidate(wordBooksProvider);
      ref.invalidate(libraryWordsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${list.title} 新增 ${result.inserted} · 已有 ${result.reused}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.any);
      if (file == null || !mounted) return;
      final name = file.name.toLowerCase();
      if (!name.endsWith('.csv') &&
          !name.endsWith('.tsv') &&
          !name.endsWith('.txt')) {
        throw const FormatException('请选择 .csv、.tsv 或 .txt');
      }
      final bytes = await file.readAsBytes();
      final preview = _service.parseBytes(bytes);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _preview = preview;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || preview.drafts.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final result = await db.transaction(() async {
        final book = await db.createWordBook(
          name: _fileName ?? '英语词表',
          sourceFileName: _fileName ?? 'english.csv',
          language: 'en',
        );
        return db.importWords(
          wordBookId: book,
          drafts: preview.drafts,
          source: _fileName ?? 'english.csv',
          language: 'en',
        );
      });
      ref.invalidate(homeCountsProvider);
      ref.invalidate(wordBooksProvider);
      ref.invalidate(libraryWordsProvider);
      ref.invalidate(studyControllerProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('英语词库新增 ${result.inserted} · 复用 ${result.reused}'),
        ),
      );
      context.go('/library');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importAtlas() async {
    setState(() {
      _busy = true;
      _error = null;
      _stage = '正在读取图鉴索引';
    });
    try {
      const remote = AtlasRemote();
      final index = await remote.loadIndex();
      var inserted = 0;
      var reused = 0;
      for (var chunk = 0; chunk < index.chunks; chunk++) {
        if (!mounted) return;
        setState(() => _stage = '正在导入 ${chunk + 1} / ${index.chunks}');
        final entries = await remote.loadChunk(chunk);
        final result = await ref
            .read(databaseProvider)
            .importAtlasEntries(entries);
        inserted += result.inserted;
        reused += result.reused;
      }
      ref.invalidate(homeCountsProvider);
      ref.invalidate(wordBooksProvider);
      ref.invalidate(libraryWordsProvider);
      ref.invalidate(studyControllerProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('词光图鉴新增 $inserted · 合并 $reused。已有进度保持不变。')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('导入英语词表')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('可以一键导入内置词表，或自己选择 CSV / TSV。这些词只进入英语词库。'),
            const SizedBox(height: 8),
            const Text(
              '$atlasAttribution。$atlasDisclaimer 插画和录音在打开词条时再下载，不会写入备份。',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _importAtlas,
              child: const Text('导入词光图鉴（7,298 词）'),
            ),
            if (_stage.isNotEmpty) ...[const SizedBox(height: 8), Text(_stage)],
            const SizedBox(height: 12),
            for (final list in englishBuiltInLists)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _importBuiltIn(list),
                  child: Text('导入${list.title}'),
                ),
              ),
            const SizedBox(height: 8),
            const Text('自己的表：第一行是表头。需要「词头」和「中文」，可以带上 IPA、词性、例句、例句中文。'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName ?? '选择 CSV 或 TSV'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (preview != null) ...[
              const SizedBox(height: 16),
              Text('有效 ${preview.drafts.length} · 跳过 ${preview.invalidRows}'),
              for (final word in preview.drafts.take(8))
                ListTile(
                  title: Text(word.korean),
                  subtitle: Text(
                    [
                      word.meaningZh,
                      if (word.ipa != null) word.ipa,
                      if (word.partOfSpeech != null) word.partOfSpeech,
                    ].join(' · '),
                  ),
                ),
              FilledButton(
                onPressed: _busy || preview.drafts.isEmpty ? null : _import,
                child: Text(_busy ? '正在导入…' : '导入到英语词库'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
