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
  final Future<String> text;
  if (ready is AiDeepSeekClient) {
    text = ready.mnemonic(word, AiCancellation());
  } else if (ready is AiProxyClient) {
    text = ready.mnemonic(word, AiCancellation());
  } else {
    throw const AiException('not_configured');
  }
  final note = await text;
  await database.saveSetting(key, note);
  return note;
}
