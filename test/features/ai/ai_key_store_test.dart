import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/features/ai/data/ai_key_store.dart';

class DelayedStore implements AiKeyStore {
  final loaded = Completer<String?>();
  String? value;
  bool failWrite = false, failDelete = false;
  @override
  Future<String?> read() => loaded.future;
  @override
  Future<void> write(String key) async {
    if (failWrite) throw Exception('platform-error-with-secret');
    value = key;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw Exception('platform-error-with-secret');
    value = null;
  }
}

void main() {
  test('save waits for startup read and then keeps the new value', () async {
    final store = DelayedStore();
    final keys = AiKeyController(store);
    addTearDown(keys.dispose);
    final save = keys.save('new-test-key');
    store.loaded.complete('previous-test-key');
    await save;
    expect(await keys.current(), 'new-test-key');
    expect(store.value, 'new-test-key');
  });
  test(
    'storage failures retain current state and never echo platform errors',
    () async {
      final store = DelayedStore();
      final keys = AiKeyController(store);
      addTearDown(keys.dispose);
      store.loaded.complete('existing-test-key');
      await keys.ready;
      store.failWrite = true;
      await expectLater(
        keys.save('new-test-key'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(await keys.current(), 'existing-test-key');
      store.failDelete = true;
      await expectLater(keys.clear(), throwsFormatException);
      expect(await keys.current(), 'existing-test-key');
      store.failDelete = false;
      await keys.clear();
      expect(await keys.current(), isEmpty);
    },
  );
}
