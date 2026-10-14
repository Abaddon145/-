import {loadConfig} from './config.js';
import {OpenAIProvider} from './provider.js';
import {createApp} from './server.js';

try {
  const config = loadConfig(process.env);
  const server = createApp(config, new OpenAIProvider(config));
  server.requestTimeout = config.timeoutMs + 5000;
  server.headersTimeout = 10000;
  server.listen(config.port, config.host, () => console.log('KoreanMemo AI proxy listening'));
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => server.close());
} catch {
  // Configuration validators can contain secrets in their diagnostic values.
  console.error('Invalid AI proxy configuration; check .env against .env.example');
  process.exitCode = 1;
}
