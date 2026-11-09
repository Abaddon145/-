import 'dart:convert';
import 'dart:typed_data';

import '../../../core/database/backup_limits.dart';

export '../../../core/database/backup_limits.dart';

/// Pretty JSON when it fits; compact JSON if that is what keeps the file
/// restorable. Throws when even the compact form is over [maxBytes].
Uint8List encodeBackupFile(
  Map<String, Object?> snapshot, {
  int maxBytes = maxBackupBytes,
}) {
  var encoded = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(snapshot),
  );
  if (encoded.length > maxBytes) {
    encoded = utf8.encode(jsonEncode(snapshot));
  }
  if (encoded.length > maxBytes) {
    final size = (encoded.length / (1024 * 1024)).toStringAsFixed(1);
    final cap = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
    throw FormatException(
      '备份约 $size MB，超过 $cap MB，当前版本无法恢复。请关闭「文件备份包含 AI 数据」或减少词条后再导出。本次未保存文件。',
    );
  }
  return Uint8List.fromList(encoded);
}
