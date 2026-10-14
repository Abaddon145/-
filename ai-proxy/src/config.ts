import {z} from 'zod';
export interface Config {
  host: string; port: number; baseURL: string; model: string; apiKey: string;
  accessToken: string; origins: string[]; api: 'responses' | 'chat';
  outputMode: 'json_schema' | 'json_object' | 'text'; timeoutMs: number;
  requestsPerMinute: number; concurrency: number; maxQueue: number; retries: number;
}
export function loadConfig(env: NodeJS.ProcessEnv): Config {
  const integer = (name: string, fallback: number, max: number) =>
    z.coerce.number().int().min(1).max(max).parse(env[name] ?? fallback);
  const baseURL = z.url().parse(env.MODEL_BASE_URL ?? 'https://api.openai.com/v1');
  if (new URL(baseURL).protocol !== 'https:' && !['localhost', '127.0.0.1'].includes(new URL(baseURL).hostname)) {
    throw new Error('MODEL_BASE_URL requires HTTPS');
  }
  return {
    host: env.HOST ?? '127.0.0.1', port: integer('PORT', 8787, 65535), baseURL,
    model: env.MODEL_NAME?.trim() ?? '', apiKey: env.MODEL_API_KEY ?? '',
    accessToken: z.string().min(24).parse(env.PROXY_ACCESS_TOKEN),
    origins: (env.ALLOWED_ORIGINS ?? '').split(',').map(s => s.trim()).filter(Boolean),
    api: z.enum(['responses', 'chat']).parse(env.PROVIDER_API ?? 'responses'),
    outputMode: z.enum(['json_schema', 'json_object', 'text']).parse(env.OUTPUT_MODE ?? 'json_schema'),
    timeoutMs: integer('REQUEST_TIMEOUT_MS', 60000, 180000),
    requestsPerMinute: integer('REQUESTS_PER_MINUTE', 20, 10000),
    concurrency: integer('CONCURRENCY', 2, 2), maxQueue: integer('MAX_QUEUE_SIZE', 40, 200),
    retries: z.coerce.number().int().min(0).max(1).parse(env.MAX_RETRIES ?? 0),
  };
}
