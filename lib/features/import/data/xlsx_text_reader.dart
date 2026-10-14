import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads vocabulary text without depending on workbook styles or number formats.
class XlsxTextReader {
  Map<String, List<List<String>>> read(Uint8List bytes) {
    if (bytes.isEmpty) throw const FormatException('文件为空，请重新选择已下载的.xlsx文件');
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.files.fold<int>(0, (sum, file) => sum + file.size) > 100 * 1024 * 1024) {
        throw const FormatException('工作簿展开后过大，请分批导入');
      }
      XmlDocument? document(String path) {
        final file = archive.findFile(path);
        return file == null ? null : XmlDocument.parse(utf8.decode(file.content as List<int>));
      }
      final workbook = document('xl/workbook.xml');
      final rels = document('xl/_rels/workbook.xml.rels');
      if (workbook == null || rels == null) {
        throw const FormatException('不是有效的.xlsx工作簿；请在Excel或WPS中另存为.xlsx');
      }
      final targets = <String, String>{};
      for (final rel in rels.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Relationship')) {
        if (rel.getAttribute('TargetMode') == 'External') continue;
        final target = rel.getAttribute('Target') ?? '';
        final uri = Uri.parse('xl/workbook.xml').resolve(target);
        targets[rel.getAttribute('Id') ?? ''] = uri.path;
      }
      final shared = document('xl/sharedStrings.xml');
      String text(XmlElement e) => e.descendants.whereType<XmlElement>()
          .where((n) => n.name.local == 't').map((n) => n.innerText).join();
      final strings = shared?.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == 'si').map(text).toList() ?? <String>[];
      final result = <String, List<List<String>>>{};
      for (final sheet in workbook.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sheet')) {
        final id = sheet.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
        final path = targets[id];
        if (path == null) continue;
        final data = document(path.startsWith('/') ? path.substring(1) : path);
        if (data == null) continue;
        final rows = <List<String>>[];
        for (final row in data.descendants.whereType<XmlElement>().where((e) => e.name.local == 'row')) {
          final values = <String>[];
          for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
            final ref = cell.getAttribute('r') ?? '';
            var column = 0;
            for (final code in ref.toUpperCase().codeUnits.takeWhile((c) => c >= 65 && c <= 90)) {
              column = column * 26 + code - 64;
            }
            final index = column == 0 ? values.length : column - 1;
            if (index > 16383) throw const FormatException('工作表列数超出Excel范围');
            while (values.length <= index) { values.add(''); }
            final raw = cell.childElements.where((e) => e.name.local == 'v').firstOrNull?.innerText ?? '';
            final type = cell.getAttribute('t');
            final sharedIndex = int.tryParse(raw);
            values[index] = (type == 'inlineStr' ? text(cell) : type == 's'
                ? (sharedIndex != null && sharedIndex >= 0 && sharedIndex < strings.length ? strings[sharedIndex] : '')
                : type == 'e' ? '' : raw).trim();
          }
          if (values.any((value) => value.isNotEmpty)) rows.add(values);
          if (rows.length > 100000) throw const FormatException('单表超过10万行，请分批导入');
        }
        if (rows.isNotEmpty) result[sheet.getAttribute('name') ?? '工作表'] = rows;
      }
      if (result.isEmpty) throw const FormatException('Excel中没有包含数据的工作表');
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取工作簿，请在Excel或WPS中另存为.xlsx后重试（加密文件请先取消密码）');
    }
  }
}
