import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uuid/uuid.dart';
import 'package:korean_memo/core/database/app_database.dart';
import 'package:korean_memo/features/ai/data/ai_client.dart';
import 'package:korean_memo/features/ai/domain/ai_models.dart';
import 'package:korean_memo/features/ai/domain/ai_providers.dart';
import 'package:korean_memo/features/study/domain/providers.dart';
import 'fixtures.dart';

void main() {
  test(
    'first request after reopening awaits the saved model and device key',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.saveSetting('ai_connection_mode', 'deepseek');
      await db.saveSetting('ai_deepseek_model', 'saved-custom-model');
      final word = await addAiWord(db, '압력');
      final request = AiRequest(
        requestId: const Uuid().v4(),
        word: word,
        context: '工厂设备',
        type: 'complete',
      );
      final store = TestAiKeyStore()..value = 'sk-saved-device-test';
      var calls = 0;
      http.Request? sent;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(store),
          aiHttpClientFactoryProvider.overrideWithValue(
            () => MockClient((r) async {
              calls++;
              sent = r;
              return http.Response(
                jsonEncode({
                  'model': 'saved-custom-model',
                  'choices': [
                    {
                      'finish_reason': 'stop',
                      'message': {
                        'content': jsonEncode(suggestionFor(request).result),
                      },
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Do not pre-load any FutureProvider before the very first call.
      final result = await container
          .read(aiGatewayProvider)
          .generate(request, AiCancellation());
      expect(result.model, 'saved-custom-model');
      expect(sent!.url.host, 'api.deepseek.com');
      expect(sent!.headers['Authorization'], 'Bearer sk-saved-device-test');
      expect((jsonDecode(sent!.body) as Map)['model'], 'saved-custom-model');
      expect(calls, 1);
    },
  );
  test(
    'first call waits for saved proxy mode and never sends to DeepSeek',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.saveSetting('ai_connection_mode', 'proxy');
      await db.saveSetting(
        'ai_proxy_url',
        'https://proxy-test.invalid/private',
      );
      var calls = 0;
      http.Request? sent;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(TestAiKeyStore()),
          aiHttpClientFactoryProvider.overrideWithValue(
            () => MockClient((r) async {
              calls++;
              sent = r;
              return http.Response(
                jsonEncode({
                  'status': 'ready',
                  'promptVersion': aiPromptVersion,
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(aiCredentialProvider.notifier).state =
          'proxy-test-credential';
      expect(await container.read(aiGatewayProvider).health(), '服务已连接');
      expect(sent!.url.toString(), 'https://proxy-test.invalid/private/health');
      expect(sent!.headers['Authorization'], 'Bearer proxy-test-credential');
      expect(calls, 1);
    },
  );
  test(
    'cancelled request cannot begin HTTP after configuration finishes loading',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final word = await addAiWord(db, '시험');
      final request = AiRequest(
        requestId: const Uuid().v4(),
        word: word,
        context: '日常韩语',
        type: 'complete',
      );
      final loading = Completer<AiGateway>();
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          aiKeyStoreProvider.overrideWithValue(
            TestAiKeyStore()..value = 'sk-test',
          ),
          aiHttpClientFactoryProvider.overrideWithValue(
            () => MockClient((r) async {
              calls++;
              throw StateError('must not send');
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      final gateway = AiDeferredGateway(() => loading.future);
      final cancel = AiCancellation();
      final pending = gateway.generate(request, cancel);
      final check = expectLater(
        pending,
        throwsA(isA<AiException>().having((e) => e.code, 'code', 'cancelled')),
      );
      cancel.cancel();
      loading.complete(container.read(aiGatewayProvider));
      await check;
      expect(calls, 0);
    },
  );
}
