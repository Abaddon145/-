import {createServer, type IncomingMessage} from 'node:http';
import {createHash, timingSafeEqual} from 'node:crypto';
import type {Config} from './config.js';
import type {Provider} from './provider.js';
import {Scheduler} from './scheduler.js';
import {AiError, MAX_BODY_BYTES, PROMPT_VERSION, requestSchema} from './schema.js';

async function body(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new AiError('request_too_large', 413);
    chunks.push(Buffer.from(chunk));
  }
  try {return JSON.parse(Buffer.concat(chunks).toString('utf8'));}
  catch {throw new AiError('invalid_request', 400);}
}
export function createApp(config: Config, provider: Provider) {
  const scheduler = new Scheduler(config, provider);
  const tokenHash = createHash('sha256').update(`Bearer ${config.accessToken}`).digest();
  return createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('Vary', 'Origin');
    const origin = req.headers.origin;
    const reply = (status: number, value: unknown) => {if (!res.destroyed) {res.statusCode = status; res.end(JSON.stringify(value));}};
    if (origin && !config.origins.includes(origin)) {reply(403, {error: {code: 'origin_denied'}}); return;}
    if (origin) res.setHeader('Access-Control-Allow-Origin', origin);
    if (req.method === 'OPTIONS') {
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      res.statusCode = 204; res.end(); return;
    }
    if (!timingSafeEqual(tokenHash, createHash('sha256').update(req.headers.authorization ?? '').digest())) {
      reply(401, {error: {code: 'unauthorized'}}); return;
    }
    const cancellation = new AbortController();
    const cancel = () => cancellation.abort(new AiError('cancelled', 499));
    req.on('aborted', cancel);
    const onClose = () => {if (!res.writableEnded) cancel();};
    res.on('close', onClose);
    try {
      if (req.method === 'GET' && req.url === '/health') {
        reply(200, {status: config.apiKey && config.model ? 'ready' : 'not_configured',
          promptVersion: PROMPT_VERSION, api: config.api, outputMode: config.outputMode,
          limitScope: 'single_process', concurrency: config.concurrency}); return;
      }
      if (req.method !== 'POST' || !['/v1/complete', '/v1/explain'].includes(req.url ?? '')) {
        throw new AiError('not_found', 404);
      }
      if (!req.headers['content-type']?.startsWith('application/json')) throw new AiError('invalid_request', 415);
      if (Number(req.headers['content-length']) > MAX_BODY_BYTES) throw new AiError('request_too_large', 413);
      const parsed = requestSchema.safeParse(await body(req));
      if (!parsed.success) throw new AiError('invalid_request', 400);
      const result = await scheduler.run(parsed.data, req.url === '/v1/complete' ? 'complete' : 'explain', cancellation.signal);
      reply(200, {result, model: config.model, generatedAt: new Date().toISOString(), promptVersion: PROMPT_VERSION});
    } catch (error) {
      const safe = error instanceof AiError ? error : new AiError('internal_error', 500);
      if (safe.status === 429) res.setHeader('Retry-After', '60');
      reply(safe.status, {error: {code: safe.code}});
    } finally {req.off('aborted', cancel); res.off('close', onClose);}
  });
}
