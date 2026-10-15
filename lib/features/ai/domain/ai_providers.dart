import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../study/domain/providers.dart';
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
  (ref) => AiKeyController(ref.watch(aiKeyStoreProvider)),
);
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
final aiGatewayProvider = Provider<AiGateway>(
  (ref) => ref.watch(aiConnectionModeProvider).valueOrNull == 'proxy'
      ? AiProxyClient(
          address: ref.watch(aiAddressProvider).valueOrNull ?? '',
          credential: ref.watch(aiCredentialProvider),
        )
      : AiDeepSeekClient(
          apiKey: ref.watch(aiApiKeyProvider),
          apiKeyLoader: ref.watch(aiApiKeyProvider.notifier).current,
          model: ref.watch(aiModelProvider).valueOrNull ?? 'deepseek-flash',
        ),
);
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
