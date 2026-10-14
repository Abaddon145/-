import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {spawnSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import type {Config} from '../src/config.js';
import {loadConfig} from '../src/config.js';
import {AiError, parseResult, PROMPT_VERSION, type AiRequest, type AiResult} from '../src/schema.js';
import {OpenAIProvider, type Provider} from '../src/provider.js';
import {Scheduler} from '../src/scheduler.js';
import {createApp} from '../src/server.js';

const config: Config = {host: '127.0.0.1', port: 0, baseURL: 'https://unit-test.invalid/v1',
  model: 'unit-test-model', apiKey: 'unit-test-model-key', accessToken: 'unit-test-proxy-credential-only',
  origins: ['https://abaddon145.github.io'], api: 'responses', outputMode: 'json_schema',
  timeoutMs: 1000, concurrency: 2, maxQueue: 40, requestsPerMinute: 20, retries: 0};
const request = (): AiRequest => ({requestId: randomUUID(), wordId: 12, originalTerm: '시험', context: '日常韩语',
  meaningZh: '', partOfSpeech: '', baseForm: '', exampleKo: '', exampleZh: '', style: 'default', exampleCount: 1});
const result = (r: AiRequest): AiResult => ({requestId: r.requestId, wordId: r.wordId,
  originalTerm: r.originalTerm, context: r.context, meaningZh: '测试释义', partOfSpeech: '名词',
  baseForm: '', collocations: [], exampleKo: '', exampleZh: '', workExampleKo: '', workExampleZh: '',
  usageNote: '', grammarNote: '', ambiguityNotes: [], confusingWords: [], terminologyNote: '',
  suspectedTypo: false, suggestedSpellings: [], needsMoreContext: false});
const errorCode = (code: string) => (error: unknown) => error instanceof AiError && error.code === code;

test('valid output, required fields, invalid JSON, limits and identity validation', () => {
  const r = request(), valid = result(r);
  assert.deepEqual(parseResult(JSON.stringify(valid), r), valid);
  for (const value of ['', null, undefined]) assert.throws(() => parseResult(value, r), errorCode('empty_response'));
  assert.throws(() => parseResult('{', r), errorCode('invalid_json'));
  assert.throws(() => parseResult(JSON.stringify({...valid, meaningZh: undefined}), r), errorCode('invalid_response'));
  assert.throws(() => parseResult(JSON.stringify({...valid, meaningZh: 'a'.repeat(2001)}), r), errorCode('invalid_response'));
  assert.throws(() => parseResult(JSON.stringify({...valid, collocations: Array(7).fill('x')}), r), errorCode('invalid_response'));
  for (const change of [{wordId: 44}, {requestId: randomUUID()}, {context: '不同'}, {originalTerm: '另一词'}]) {
    assert.throws(() => parseResult(JSON.stringify({...valid, ...change}), r), errorCode('identity_mismatch'));
  }
});

function mockProvider(c: Config, reply: (payload: Record<string, unknown>) => unknown) {
  const bodies: Record<string, unknown>[] = [];
  const provider = new OpenAIProvider(c, (async (_url, init) => {
    const payload = JSON.parse(init?.body as string) as Record<string, unknown>; bodies.push(payload);
    assert.ok(init?.signal);
    return new Response(JSON.stringify(reply(payload)), {status: 200, headers: {'content-type': 'application/json'}});
  }) as typeof fetch);
  return {provider, bodies};
}
function response(content: unknown, status = 'completed') {
  return {id: 'unit-test-response', object: 'response', status,
    output: [{type: 'message', id: 'message', role: 'assistant', status: 'completed', content}]};
}

test('official SDK responses sends strict JSON Schema, no storage and validates output', async () => {
  const r = request();
  const {provider, bodies} = mockProvider(config, () => response([{type: 'output_text', text: JSON.stringify(result(r)), annotations: []}]));
  assert.deepEqual(await provider.generate(r, 'complete', new AbortController().signal), result(r));
  assert.equal(bodies.length, 1); assert.equal(bodies[0]?.store, false);
  const format = (bodies[0]?.text as {format: {strict: boolean; type: string}}).format;
  assert.equal(format.strict, true); assert.equal(format.type, 'json_schema');
});
for (const [name, content, status, code] of [
  ['refusal', [{type: 'refusal', refusal: 'test refusal'}], 'completed', 'refused'],
  ['truncation', [], 'incomplete', 'truncated'],
  ['empty', [], 'completed', 'empty_response'],
  ['invalid JSON', [{type: 'output_text', text: '{', annotations: []}], 'completed', 'invalid_json'],
] as const) test(`responses ${name} is distinguished`, async () => {
  const {provider} = mockProvider(config, () => response(content, status));
  await assert.rejects(provider.generate(request(), 'explain', new AbortController().signal), errorCode(code));
});

test('compatible chat json_object/text capabilities do not assume strict schema support', async () => {
  for (const mode of ['json_object', 'text'] as const) {
    const r = request();
    const {provider, bodies} = mockProvider({...config, api: 'chat', outputMode: mode}, () => ({
      choices: [{finish_reason: 'stop', message: {content: JSON.stringify(result(r))}}]}));
    await provider.generate(r, 'explain', new AbortController().signal);
    assert.deepEqual(bodies[0]?.response_format, mode === 'text' ? undefined : {type: 'json_object'});
  }
});
for (const [reason, refusal, code] of [['length', null, 'truncated'], ['stop', 'no', 'refused'],
  ['content_filter', null, 'refused']] as const) test(`chat ${reason}/${refusal} is distinguished`, async () => {
  const {provider} = mockProvider({...config, api: 'chat'}, () => ({choices: [{finish_reason: reason, message: {content: '', refusal}}]}));
  await assert.rejects(provider.generate(request(), 'complete', new AbortController().signal), errorCode(code));
});
test('model service 429 is sanitized and SDK retries are disabled', async () => {
  let calls = 0;
  const provider = new OpenAIProvider(config, (async () => {
    calls++; return new Response(JSON.stringify({error: {message: config.apiKey}}), {status: 429});
  }) as typeof fetch);
  await assert.rejects(provider.generate(request(), 'complete', new AbortController().signal), errorCode('rate_limited'));
  assert.equal(calls, 1);
});
test('AbortSignal reaches the actual SDK fetch and aborts it', async () => {
  const controller = new AbortController(); let aborted = false;
  let started!: () => void; const entered = new Promise<void>(resolve => {started = resolve;});
  const provider = new OpenAIProvider(config, (async (_url, init) => {
    started();
    await new Promise<void>((_resolve, reject) => init!.signal!.addEventListener('abort', () => {
      aborted = true; reject(new DOMException('aborted', 'AbortError'));
    }, {once: true}));
    throw new Error('unreachable');
  }) as typeof fetch);
  const call = provider.generate(request(), 'complete', controller.signal);
  await entered; controller.abort(new AiError('cancelled', 499));
  await assert.rejects(call, errorCode('cancelled')); assert.equal(aborted, true);
});

test('queue concurrency never exceeds two and partial failures do not discard success', async () => {
  let running = 0, peak = 0;
  const provider: Provider = {async generate(r, _type, signal) {
    peak = Math.max(peak, ++running);
    try {await delay(8, undefined, {signal}); if (r.wordId === 1) throw new AiError('provider_error'); return result(r);}
    finally {running--;}
  }};
  const scheduler = new Scheduler(config, provider);
  const results = await Promise.allSettled(Array.from({length: 6}, (_, i) => scheduler.run({...request(), wordId: i + 1}, 'complete', new AbortController().signal)));
  assert.equal(peak, 2); assert.equal(results.filter(r => r.status === 'fulfilled').length, 5);
});
test('active and queued requests cancel; queued requests never invoke provider', async () => {
  let started = 0, aborted = 0;
  const provider: Provider = {async generate(r, _type, signal) {
    started++; try {await delay(1000, undefined, {signal}); return result(r);} finally {if (signal.aborted) aborted++;}
  }};
  const scheduler = new Scheduler(config, provider), controller = new AbortController();
  const pending = Array.from({length: 5}, () => scheduler.run(request(), 'complete', controller.signal));
  const settled = Promise.allSettled(pending);
  await delay(10); controller.abort(new AiError('cancelled', 499));
  const results = await settled;
  assert.equal(started, 2); assert.equal(aborted, 2); assert.ok(results.every(r => r.status === 'rejected'));
});
test('timeout aborts provider, rate interval applies and queue overflow is 429', async () => {
  let calls = 0;
  const provider: Provider = {async generate(r, _t, signal) {calls++; await delay(100, undefined, {signal}); return result(r);}};
  const scheduler = new Scheduler({...config, timeoutMs: 30, requestsPerMinute: 1, maxQueue: 2}, provider);
  const first = scheduler.run(request(), 'complete', new AbortController().signal);
  const second = scheduler.run(request(), 'complete', new AbortController().signal);
  const outcomes = Promise.allSettled([first, second]);
  await assert.rejects(scheduler.run(request(), 'complete', new AbortController().signal), errorCode('rate_limited'));
  const settled = await outcomes;
  assert.equal(calls, 1);
  assert.ok(settled.every(r => r.status === 'rejected' && r.reason.code === 'timeout'));
});
test('central retry policy alone controls retries', async () => {
  for (const retries of [0, 1]) {
    let calls = 0;
    const scheduler = new Scheduler({...config, retries}, {async generate(r) {
      if (++calls === 1) throw new AiError('provider_error'); return result(r);
    }});
    const pending = scheduler.run(request(), 'complete', new AbortController().signal);
    if (retries) await pending; else await assert.rejects(pending, errorCode('provider_error'));
    assert.equal(calls, retries + 1);
  }
});

test('proxy auth, CORS, request size, validation, health and safe response metadata', async t => {
  let calls = 0;
  const server = createApp(config, {async generate(r) {calls++; return result(r);}});
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise<void>(resolve => server.close(() => resolve())));
  const address = server.address(); assert.ok(address && typeof address !== 'string');
  const url = `http://127.0.0.1:${address.port}`;
  const headers = {'authorization': `Bearer ${config.accessToken}`, 'content-type': 'application/json'};
  assert.equal((await fetch(`${url}/health`)).status, 401);
  const health = await fetch(`${url}/health`, {headers}); assert.equal(health.status, 200);
  assert.equal((await health.json() as {promptVersion: string}).promptVersion, PROMPT_VERSION);
  assert.equal((await fetch(`${url}/health`, {headers: {...headers, origin: 'https://untrusted.invalid'}})).status, 403);
  assert.equal((await fetch(`${url}/v1/complete`, {method: 'POST', headers, body: 'a'.repeat(16385)})).status, 413);
  assert.equal((await fetch(`${url}/v1/complete`, {method: 'POST', headers, body: '{}'})).status, 400);
  const r = request();
  const reply = await fetch(`${url}/v1/complete`, {method: 'POST', headers: {...headers, origin: config.origins[0]!}, body: JSON.stringify(r)});
  assert.equal(reply.status, 200); assert.equal(reply.headers.get('access-control-allow-origin'), config.origins[0]);
  const output = await reply.text(); assert.ok(!output.includes(config.apiKey)); assert.ok(!output.includes(config.accessToken));
  assert.equal(calls, 1); assert.deepEqual(JSON.parse(output).result, result(r));
});
test('HTTP disconnect cancels the running provider', async t => {
  let begin!: () => void, finish!: () => void;
  const entered = new Promise<void>(resolve => {begin = resolve;}), aborted = new Promise<void>(resolve => {finish = resolve;});
  const server = createApp(config, {async generate(r, _type, signal) {
    begin(); try {await delay(500, undefined, {signal}); return result(r);} finally {if (signal.aborted) finish();}
  }});
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise<void>(resolve => server.close(() => resolve())));
  const a = server.address(); assert.ok(a && typeof a !== 'string');
  const controller = new AbortController();
  const pending = fetch(`http://127.0.0.1:${a.port}/v1/explain`, {method: 'POST', signal: controller.signal,
    headers: {authorization: `Bearer ${config.accessToken}`, 'content-type': 'application/json'}, body: JSON.stringify(request())}).catch(() => undefined);
  await entered; controller.abort(); await aborted; await pending;
});
test('invalid startup configuration does not leak secret values to logs', () => {
  const sentinel = 'unit-test-sensitive-sentinel';
  const child = spawnSync(process.execPath, ['--import', 'tsx', 'src/index.ts'], {
    encoding: 'utf8', env: {...process.env, PROXY_ACCESS_TOKEN: sentinel, MODEL_API_KEY: sentinel, PORT: '-2'},
  });
  assert.equal(child.status, 1); assert.ok(!child.stderr.includes(sentinel)); assert.ok(!child.stdout.includes(sentinel));
  assert.throws(() => loadConfig({PROXY_ACCESS_TOKEN: config.accessToken, CONCURRENCY: '3'}));
});
test('PWA worker never caches authenticated requests, even for same-origin proxies', async () => {
  let handler!: (event: {request: Request; respondWith: (reply: unknown) => void}) => void;
  const source = await readFile(new URL('../../web/offline_worker.js', import.meta.url), 'utf8');
  runInNewContext(source, {URL, self: {location: new URL('https://unit-test.example/-/offline_worker.js'),
    addEventListener(name: string, fn: typeof handler) {if (name === 'fetch') handler = fn;}},
    caches: {open: async () => ({match: async () => new Response('static test asset')})},
  });
  let intercepted = false;
  handler({request: new Request('https://unit-test.example/-/ai/health', {headers: {authorization: 'Bearer unit-test-credential'}}),
    respondWith() {intercepted = true;}});
  assert.equal(intercepted, false);
  handler({request: new Request('https://unit-test.example/-/manifest.json'), respondWith() {intercepted = true;}});
  assert.equal(intercepted, true);
});
