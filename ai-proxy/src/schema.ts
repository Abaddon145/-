import {z} from 'zod';

export const PROMPT_VERSION = 'ko-zh-v1';
export const MAX_BODY_BYTES = 16384;
export const MAX_OUTPUT_BYTES = 32768;
const text = (limit: number) => z.string().max(limit);
const short = text(200);
const note = text(2000);
const list = z.array(text(500)).max(6);
export const requestSchema = z.object({
  requestId: z.string().uuid(), wordId: z.number().int().positive(),
  originalTerm: short.min(1), context: text(600).min(1),
  meaningZh: note, partOfSpeech: short, baseForm: short,
  exampleKo: text(1000), exampleZh: text(1000),
  style: z.enum(['default', 'simpler', 'work', 'confusing', 'example']),
  exampleCount: z.number().int().min(1).max(3),
}).strict();
export type AiRequest = z.infer<typeof requestSchema>;
export type TaskType = 'complete' | 'explain';
export const resultSchema = z.object({
  requestId: z.string().uuid(), wordId: z.number().int().positive(),
  originalTerm: short.min(1), context: text(600).min(1),
  meaningZh: note, partOfSpeech: short, baseForm: short,
  collocations: list, exampleKo: text(1000), exampleZh: text(1000),
  workExampleKo: text(1000), workExampleZh: text(1000),
  usageNote: note, grammarNote: note, ambiguityNotes: list,
  confusingWords: list, terminologyNote: note,
  suspectedTypo: z.boolean(), suggestedSpellings: z.array(short).max(5),
  needsMoreContext: z.boolean(),
}).strict();
export type AiResult = z.infer<typeof resultSchema>;

export class AiError extends Error {
  constructor(public code: string, public status = 502) { super(code); }
}
export function parseResult(content: string | null | undefined, request: AiRequest): AiResult {
  if (!content?.trim()) throw new AiError('empty_response');
  if (Buffer.byteLength(content) > MAX_OUTPUT_BYTES) throw new AiError('invalid_response');
  let raw: unknown;
  try {raw = JSON.parse(content);} catch {throw new AiError('invalid_json');}
  const parsed = resultSchema.safeParse(raw);
  if (!parsed.success) throw new AiError('invalid_response');
  const result = parsed.data;
  if (result.requestId !== request.requestId || result.wordId !== request.wordId ||
      result.originalTerm !== request.originalTerm || result.context !== request.context) {
    throw new AiError('identity_mismatch');
  }
  return result;
}
