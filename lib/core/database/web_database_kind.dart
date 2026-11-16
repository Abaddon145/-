import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

enum WebDatabaseKind { unknown, opfs, shared, unsafe, memory }

final webDatabaseKind = ValueNotifier<WebDatabaseKind>(WebDatabaseKind.unknown);

/// Drift picks [WasmStorageImplementation.opfsLocks] when that browser can use
/// it. Record the result so the home screen can warn only for unsafe storage.
void noteWebDatabaseKind(WasmDatabaseResult result) {
  webDatabaseKind.value = switch (result.chosenImplementation) {
    WasmStorageImplementation.opfsShared ||
    WasmStorageImplementation.opfsLocks => WebDatabaseKind.opfs,
    WasmStorageImplementation.sharedIndexedDb => WebDatabaseKind.shared,
    WasmStorageImplementation.unsafeIndexedDb => WebDatabaseKind.unsafe,
    WasmStorageImplementation.inMemory => WebDatabaseKind.memory,
  };
}
