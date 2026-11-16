import 'dart:typed_data';

import 'backup_delivery.dart';

Future<void> requestPersistentStorage() async {}

Future<BackupDelivery> deliverBackupFile(
  Uint8List bytes,
  String fileName,
) async => BackupDelivery.downloadOnly;
