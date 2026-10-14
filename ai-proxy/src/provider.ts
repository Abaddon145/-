import OpenAI from 'openai';
import {z} from 'zod';
import type {Config} from './config.js';
import {systemPrompt, promptFor} from './prompts.js';
import {AiError, resultSchema, parseResult, type AiRequest, type AiResult, type TaskType} from './schema.js';

export interface Provider {
  generate(request: AiRequest, type: TaskType, signal: AbortSignal): Promise<AiResult>;
}
export class OpenAIProvider implements Provider {
  private client: OpenAI;
  constructor(private config: Config, fetch?: typeof globalThis.fetch) {
    this.client = new OpenAI({apiKey: config.apiKey || 'unconfigured', baseURL: config.baseURL,
      maxRetries: 0, timeout: config.timeoutMs, ...(fetch ? {fetch} : {})});
  }
  async generate(request: AiRequest, type: TaskType, signal: AbortSignal): Promise<AiResult> {
    if (!this.config.apiKey || !this.config.model) throw new AiError('not_configured', 503);
    const schema = z.toJSONSchema(resultSchema);
    const prompt = promptFor(request, type);
    try {
      if (this.config.api === 'responses') {
        const response = await this.client.responses.create({
          model: this.config.model, instructions: systemPrompt, input: prompt,
          store: false, max_output_tokens: 4000,
          ...(this.config.outputMode === 'text' ? {} : {text: {format: this.config.outputMode === 'json_schema'
            ? {type: 'json_schema' as const, name: 'korean_memo', strict: true, schema}
            : {type: 'json_object' as const}}}),
        }, {signal});
        if (response.output.some(o => o.type === 'message' && o.content.some(c => c.type === 'refusal'))) {
          throw new AiError('refused', 422);
        }
        if (response.status === 'incomplete') throw new AiError('truncated');
        if (response.status !== 'completed') throw new AiError('provider_error');
        return parseResult(response.output_text, request);
      }
      const response = await this.client.chat.completions.create({
        model: this.config.model,
        messages: [{role: 'system', content: systemPrompt}, {role: 'user', content: prompt}],
        ...(this.config.outputMode === 'text' ? {} : {response_format: this.config.outputMode === 'json_schema'
          ? {type: 'json_schema' as const, json_schema: {name: 'korean_memo', strict: true, schema}}
          : {type: 'json_object' as const}}),
      }, {signal});
      const choice = response.choices[0];
      if (choice?.message.refusal || choice?.finish_reason === 'content_filter') throw new AiError('refused', 422);
      if (choice?.finish_reason === 'length') throw new AiError('truncated');
      if (choice && choice.finish_reason !== 'stop') throw new AiError('provider_error');
      return parseResult(choice?.message.content, request);
    } catch (error) {
      if (error instanceof AiError) throw error;
      if (signal.aborted) throw signal.reason;
      if (error instanceof OpenAI.RateLimitError) throw new AiError('rate_limited', 429);
      if (error instanceof OpenAI.APIConnectionTimeoutError) throw new AiError('timeout', 504);
      // Never return SDK messages, bodies, headers or model credentials to logs/client.
      throw new AiError('provider_error');
    }
  }
}
