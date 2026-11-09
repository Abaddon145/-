import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/time/local_day.dart';
import '../../study/domain/providers.dart';
import '../data/ai_usage.dart';
import '../data/ai_client.dart';
import '../data/ai_deepseek_client.dart';
import '../data/ai_repository.dart';
import '../data/ai_task_runner.dart';
import '../data/ai_key_store.dart';

// Optional proxy credential remains session-only; the personal DeepSeek key
// is stored separately on this device and never enters Drift or file backups.
final aiCredentialProvider = StateProvider<String>((ref) => '');
final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => DeviceAiKeyStore());
final aiApiKeyProvider = StateNotifierProvider<AiKeyController, String>(
  (ref) => AiKeyController(
    ref.watch(aiKeyStoreProvider),
    loadPersist: kIsWeb
        ? () async =>
              (await ref.read(databaseProvider).loadSetting('ai_remember_key')) ==
              'true'
        : null,
  ),
);
final aiDailyRequestCountProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(localDayProvider);
  return loadTodayDirectRequests(ref.watch(databaseProvider), DateTime.now());
});
final aiConnectionModeProvider = FutureProvider<String>(
  (ref) => ref
      .watch(databaseProvider)
      .loadSetting('ai_connection_mode')
      .then((v) => v == 'proxy' ? 'proxy' : 'deepseek'),
);
final aiModelProvider = FutureProvider<String>(
  (ref) => ref
      .watch(databaseProvider)
      .loadSetting('ai_deepseek_model')
      .then((v) => v ?? 'deepseek-flash'),
);
final aiAddressProvider = FutureProvider<String>(
  (ref) => ref
      .watch(databaseProvider)
      .loadSetting('ai_proxy_url')
      .then((v) => v ?? ''),
);
final aiContextProvider = FutureProvider<String>(
  (ref) => ref
      .watch(databaseProvider)
      .loadSetting('ai_default_context')
      .then((v) => v ?? '日常韩语'),
);
final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(databaseProvider)),
);
final aiHttpClientFactoryProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);
final aiGatewayProvider = Provider<AiGateway>((ref) {
  final mode = ref.watch(aiConnectionModeProvider.future);
  final address = ref.watch(aiAddressProvider.future);
  final model = ref.watch(aiModelProvider.future);
  final keys = ref.watch(aiApiKeyProvider.notifier);
  final credential = ref.watch(aiCredentialProvider);
  final clientFactory = ref.watch(aiHttpClientFactoryProvider);
  return AiDeferredGateway(() async {
    final values = await Future.wait([mode, address, model]);
    return values[0] == 'proxy'
        ? AiProxyClient(
            address: values[1],
            credential: credential,
            clientFactory: clientFactory,
          )
        : AiDeepSeekClient(
            apiKey: '',
            apiKeyLoader: keys.current,
            model: values[2],
            clientFactory: clientFactory,
            onRequest: () async {
              await recordDirectAiRequest(ref.read(databaseProvider));
              ref.invalidate(aiDailyRequestCountProvider);
            },
          );
  });
});
final aiTaskRunnerProvider = Provider<AiTaskRunner>((ref) {
  final runner = AiTaskRunner(
    ref.watch(aiRepositoryProvider),
    () => ref.read(aiGatewayProvider),
  );
  ref.onDispose(runner.dispose);
  return runner;
});
final aiTasksProvider = StreamProvider(
  (ref) => ref.watch(aiRepositoryProvider).watchTasks(),
);
final aiItemsProvider = StreamProvider.family(
  (ref, String id) => ref.watch(aiRepositoryProvider).watchItems(id),
);
