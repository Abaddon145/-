import PQueue from 'p-queue';
import {setTimeout as delay} from 'node:timers/promises';
import type {Config} from './config.js';
import {AiError, type AiRequest, type AiResult, type TaskType} from './schema.js';
import type {Provider} from './provider.js';

// This queue limits ONE process. It does not persist client tasks or enforce a multi-instance quota.
export class Scheduler {
  private queue: PQueue;
  constructor(private config: Config, private provider: Provider) {
    this.queue = new PQueue({concurrency: config.concurrency,
      intervalCap: config.requestsPerMinute, interval: 60000, strict: true});
  }
  async run(request: AiRequest, type: TaskType, callerSignal: AbortSignal): Promise<AiResult> {
    if (this.queue.size + this.queue.pending >= this.config.maxQueue) throw new AiError('rate_limited', 429);
    const timeout = new AbortController();
    const timer = setTimeout(() => timeout.abort(new AiError('timeout', 504)), this.config.timeoutMs);
    const signal = AbortSignal.any([callerSignal, timeout.signal]);
    try {
      for (let attempt = 0; ; attempt++) {
        signal.throwIfAborted();
        try {
          // p-queue aborting an ACTIVE add() releases its slot before the provider
          // has finished unwinding. Abort the queue signal only while waiting;
          // the real provider receives the original signal and keeps its slot
          // until the actual HTTP operation settles.
          const waiting = new AbortController();
          let started = false;
          const abortWaiting = () => {if (!started) waiting.abort(signal.reason);};
          signal.addEventListener('abort', abortWaiting, {once: true});
          let result: AiResult | undefined;
          try {
            if (signal.aborted) abortWaiting();
            result = await this.queue.add(() => {
              started = true;
              signal.throwIfAborted();
              return this.provider.generate(request, type, signal);
            }, {signal: waiting.signal});
          } finally {signal.removeEventListener('abort', abortWaiting);}
          if (!result) throw new AiError('empty_response');
          return result;
        } catch (error) {
          if (signal.aborted) throw signal.reason;
          if (!(error instanceof AiError) || !['provider_error', 'rate_limited'].includes(error.code) || attempt >= this.config.retries) throw error;
          // Every retry returns to the rate-limited queue. No retries in SDK/Flutter.
          await delay(500 * (attempt + 1), undefined, {signal});
        }
      }
    } finally {clearTimeout(timer);}
  }
}
