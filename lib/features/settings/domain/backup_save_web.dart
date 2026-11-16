import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'backup_delivery.dart';

Future<void> requestPersistentStorage() async {
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (_) {}
}

Future<BackupDelivery> deliverBackupFile(
  Uint8List bytes,
  String fileName,
) async {
  await requestPersistentStorage();
  final picked = await _writeWithPicker(bytes, fileName);
  if (picked != null) return picked;
  final shared = await _shareFile(bytes, fileName);
  if (shared != null) return shared;
  _download(bytes, fileName);
  return BackupDelivery.downloadOnly;
}

Future<BackupDelivery?> _writeWithPicker(
  Uint8List bytes,
  String fileName,
) async {
  if (!web.window.has('showSaveFilePicker')) return null;
  try {
    final options = {
      'suggestedName': fileName,
      'types': [
        {
          'description': 'JSON',
          'accept': {
            'application/json': ['.json'],
          },
        },
      ],
    }.jsify();
    final handle = await web.window
        .callMethod<JSPromise<JSObject>>('showSaveFilePicker'.toJS, options)
        .toDart;
    final writable = await handle
        .callMethod<JSPromise<JSObject>>('createWritable'.toJS)
        .toDart;
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    await writable.callMethod<JSPromise<JSAny?>>('write'.toJS, blob).toDart;
    await writable.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    return BackupDelivery.written;
  } catch (error) {
    if ('$error'.contains('AbortError')) return BackupDelivery.cancelled;
    return null;
  }
}

Future<BackupDelivery?> _shareFile(Uint8List bytes, String fileName) async {
  try {
    final file = web.File(
      [bytes.toJS].toJS,
      fileName,
      web.FilePropertyBag(type: 'application/json'),
    );
    final data = web.ShareData(files: [file].toJS, title: '词忆备份');
    if (!web.window.navigator.canShare(data)) return null;
    await web.window.navigator.share(data).toDart;
    return BackupDelivery.shared;
  } catch (error) {
    if ('$error'.contains('AbortError')) return BackupDelivery.cancelled;
    return null;
  }
}

void _download(Uint8List bytes, String fileName) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(minutes: 1), () {
    web.URL.revokeObjectURL(url);
  });
}
