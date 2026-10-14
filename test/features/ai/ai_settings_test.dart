import 'dart:convert';
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

void main() {
  testWidgets(
    'paste API key without proxy; keep secret in session across page visits but never DB or backup',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
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
      await tester.enterText(keyField, 'sk-test-session-only-secret');
      await tester.ensureVisible(find.text('保存设置'));
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(container.read(aiApiKeyProvider), 'sk-test-session-only-secret');
      expect(await db.loadSetting('ai_connection_mode'), 'deepseek');
      expect(await db.loadSetting('ai_deepseek_model'), 'deepseek-flash');
      expect(await db.loadSetting('ai_proxy_url'), isNull);
      expect(container.read(aiGatewayProvider), isA<AiDeepSeekClient>());
      final rows = await db.select(db.appSettings).get();
      expect(
        rows.map((r) => r.value).join(),
        isNot(contains('sk-test-session-only-secret')),
      );
      expect(
        jsonEncode(await db.createBackupSnapshot(includeAi: true)),
        isNot(contains('sk-test-session-only-secret')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await open();
      expect(
        tester.widget<TextField>(keyField).controller!.text,
        'sk-test-session-only-secret',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      final reopened = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(reopened.dispose);
      expect(reopened.read(aiApiKeyProvider), isEmpty);
      expect(await reopened.read(aiConnectionModeProvider.future), 'deepseek');
    },
  );
  test(
    'proxy settings and credential remain supported independently of direct key',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(db.close);
      addTearDown(container.dispose);
      await db.saveSetting('ai_connection_mode', 'proxy');
      await db.saveSetting('ai_proxy_url', 'https://unit-test.invalid');
      await container.read(aiConnectionModeProvider.future);
      await container.read(aiAddressProvider.future);
      container.read(aiCredentialProvider.notifier).state = 'proxy-only-secret';
      container.read(aiApiKeyProvider.notifier).state = 'sk-direct-only-secret';
      final gateway = container.read(aiGatewayProvider) as AiProxyClient;
      expect(gateway.credential, 'proxy-only-secret');
      expect(gateway.address, 'https://unit-test.invalid');
    },
  );
}
