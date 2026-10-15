import 'dart:convert';
import 'package:korean_memo/features/ai/data/ai_key_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/data/ai_client.dart';
import 'package:korean_memo/features/ai/data/ai_deepseek_client.dart';
import 'package:korean_memo/features/ai/domain/ai_providers.dart';
import 'package:korean_memo/features/ai/presentation/ai_settings_page.dart';
import 'package:korean_memo/features/study/domain/providers.dart';

class MemoryKeyStore implements AiKeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String key) async {
    value = key;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  testWidgets(
    'save API key once; reopen automatically, exclude from backup, and clear explicitly',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = MemoryKeyStore();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(db.close);
      addTearDown(container.dispose);
      Future<void> open() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: AiSettingsPage()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('DeepSeek API Key'), findsOneWidget);
      expect(find.text('代理地址'), findsNothing);
      final keyField = find.byKey(const ValueKey('deepseek-api-key'));
      expect(tester.widget<TextField>(keyField).obscureText, true);
      await tester.enterText(keyField, 'sk-test-device-secret');
      await tester.ensureVisible(find.text('保存设置'));
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(container.read(aiApiKeyProvider), 'sk-test-device-secret');
      expect(await db.loadSetting('ai_connection_mode'), 'deepseek');
      expect(await db.loadSetting('ai_deepseek_model'), 'deepseek-flash');
      expect(await db.loadSetting('ai_proxy_url'), isNull);
      expect(
        await (container.read(aiGatewayProvider) as AiDeferredGateway).ready,
        isA<AiDeepSeekClient>(),
      );
      final rows = await db.select(db.appSettings).get();
      expect(
        rows.map((r) => r.value).join(),
        isNot(contains('sk-test-device-secret')),
      );
      expect(
        jsonEncode(await db.createBackupSnapshot(includeAi: true)),
        isNot(contains('sk-test-device-secret')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await open();
      expect(
        tester.widget<TextField>(keyField).controller!.text,
        'sk-test-device-secret',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final reopened = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(reopened.dispose);
      await reopened.read(aiApiKeyProvider.notifier).ready;
      expect(reopened.read(aiApiKeyProvider), 'sk-test-device-secret');
      await open();
      await tester.ensureVisible(find.text('清除已保存密钥'));
      await tester.tap(find.text('清除已保存密钥'));
      await tester.pumpAndSettle();
      expect(container.read(aiApiKeyProvider), isEmpty);
      expect(store.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await reopened.read(aiConnectionModeProvider.future), 'deepseek');
    },
  );
  test(
    'proxy settings and credential remain supported independently of direct key',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = MemoryKeyStore();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(db.close);
      addTearDown(container.dispose);
      await db.saveSetting('ai_connection_mode', 'proxy');
      await db.saveSetting('ai_proxy_url', 'https://unit-test.invalid');
      await container.read(aiConnectionModeProvider.future);
      await container.read(aiAddressProvider.future);
      container.read(aiCredentialProvider.notifier).state = 'proxy-only-secret';
      await container
          .read(aiApiKeyProvider.notifier)
          .save('sk-direct-only-secret');
      final gateway =
          await (container.read(aiGatewayProvider) as AiDeferredGateway).ready
              as AiProxyClient;
      expect(gateway.credential, 'proxy-only-secret');
      expect(gateway.address, 'https://unit-test.invalid');
    },
  );
}
