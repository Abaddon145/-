import '../../../core/database/app_database.dart';
import '../domain/ai_models.dart';
import '../domain/mnemonic.dart';
import 'ai_client.dart';
import 'ai_deepseek_client.dart';

Future<String> loadOrCreateMnemonic(
  AppDatabase database,
  AiGateway gateway,
  Word word,
) async {
  final key = mnemonicCacheKey(word);
  final cached = await database.loadSetting(key);
  if (cached != null && cached.trim().isNotEmpty) return cached;
  final ready = gateway is AiDeferredGateway ? await gateway.ready : gateway;
  final text = switch (ready) {
    AiDeepSeekClient client => await client.mnemonic(word, AiCancellation()),
    AiProxyClient client => await client.mnemonic(word, AiCancellation()),
    _ => throw const AiException('not_configured'),
  };
  await database.saveSetting(key, text);
  return text;
}
