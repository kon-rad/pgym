import { HttpsError } from './errors';

export const DEFAULT_TOGETHER_MODEL = 'Qwen/Qwen3-VL-8B-Instruct';
export const MAX_JPEG_BYTES = 1_500_000;
export const MAX_INSIGHT_CHARS = 180;

export interface VisionProvider {
  analyze(jpeg: Uint8Array): Promise<string>;
}

type Fetch = typeof fetch;

export class TogetherVisionProvider implements VisionProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model = process.env.TOGETHER_MODEL || DEFAULT_TOGETHER_MODEL,
    private readonly fetchImpl: Fetch = fetch,
  ) {}

  async analyze(jpeg: Uint8Array): Promise<string> {
    if (!this.apiKey) throw new HttpsError('failed-precondition', 'Photo insight is not configured.');
    const response = await this.fetchImpl('https://api.together.xyz/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        temperature: 0.2,
        max_tokens: 80,
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: 'Give one short, positive, non-medical workout technique insight based only on visible training context. Do not identify the person, judge their body, diagnose, score, or mention sensitive traits. Return one sentence under 180 characters. If unsuitable, return REFUSE.' },
            { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${Buffer.from(jpeg).toString('base64')}` } },
          ],
        }],
      }),
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) throw new HttpsError('internal', 'The insight provider is temporarily unavailable.');
    const payload = await response.json() as { choices?: Array<{ message?: { content?: unknown } }> };
    const output = payload.choices?.[0]?.message?.content;
    if (typeof output !== 'string') throw new HttpsError('internal', 'The insight provider returned an invalid response.');
    return output;
  }
}

export async function analyzeJpeg(provider: VisionProvider, jpeg: Uint8Array): Promise<{ insight: string }> {
  if (jpeg.byteLength === 0 || jpeg.byteLength > MAX_JPEG_BYTES) {
    throw new HttpsError('invalid-argument', `JPEG must be between 1 and ${MAX_JPEG_BYTES} bytes.`);
  }
  if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8 || jpeg.at(-2) !== 0xff || jpeg.at(-1) !== 0xd9) {
    throw new HttpsError('invalid-argument', 'Body must be a valid JPEG envelope.');
  }
  const raw = (await provider.analyze(jpeg)).replace(/\s+/g, ' ').trim();
  if (!raw || /^refuse\.?$/i.test(raw)) throw new HttpsError('failed-precondition', 'No suitable workout insight was available for this photo.');
  if (raw.length > MAX_INSIGHT_CHARS || /\b(diagnos|medical|disease|injur(?:y|ed)|body fat|age|race|ethnicity)\b/i.test(raw)) {
    throw new HttpsError('internal', 'The insight provider returned an unsafe response.');
  }
  return { insight: raw };
}
