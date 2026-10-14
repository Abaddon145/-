import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../study/domain/providers.dart';
import '../data/ai_client.dart';
import '../data/ai_repository.dart';
import '../data/ai_task_runner.dart';

// Credentials live only in Riverpod memory for this app session, never Drift or backups.
final aiCredentialProvider = StateProvider<String>((ref) => '');
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
  (ref) => AiProxyClient(
    address: ref.watch(aiAddressProvider).valueOrNull ?? '',
    credential: ref.watch(aiCredentialProvider),
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
