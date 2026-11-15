/**
 * Every vision model call goes through `VisionModel`. There are two
 * implementations: `GeminiClient` below (the real, paid API) and the fake in
 * the tests. No test constructs a GeminiClient against the network.
 */

export interface TokenUsage {
  /** Prompt tokens, image included. */
  inputTokens: number;
  /** Response tokens plus any thinking tokens; both are billed as output. */
  outputTokens: number;
}

export interface VisionRequest {
  prompt: string;
  responseSchema: object;
  image: Uint8Array;
  mimeType: string;
}

export interface VisionResponse {
  /** The model's text, expected to be JSON. May be empty when the model was blocked. */
  text: string;
  usage: TokenUsage;
  /** Gemini's finish reason, for the log. */
  finishReason?: string;
}

export interface VisionModel {
  readonly modelId: string;
  analyze(req: VisionRequest): Promise<VisionResponse>;
}

export interface GeminiClientConfig {
  apiKey: string;
  modelId: string;
  /** Default https://generativelanguage.googleapis.com/v1beta */
  baseUrl?: string;
  timeoutMs?: number;
  /** For tests of the request shape. */
  fetchImpl?: typeof fetch;
}

const DEFAULT_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const MODEL_ID_PATTERN = /^[a-z0-9][a-z0-9.-]{0,99}$/;

interface GeminiReply {
  candidates?: Array<{ content?: { parts?: Array<{ text?: string }> }; finishReason?: string }>;
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number; thoughtsTokenCount?: number };
  promptFeedback?: { blockReason?: string };
}

/** The Gemini API's generateContent with structured JSON output. The key goes in a header, never the URL. */
export class GeminiClient implements VisionModel {
  readonly modelId: string;
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly timeoutMs: number;
  private readonly fetchImpl: typeof fetch;

  constructor(config: GeminiClientConfig) {
    if (!config.apiKey) throw new Error('Gemini API key is not configured');
    if (!MODEL_ID_PATTERN.test(config.modelId)) throw new Error('Gemini model ID is missing or malformed');
    this.apiKey = config.apiKey;
    this.modelId = config.modelId;
    this.baseUrl = (config.baseUrl ?? DEFAULT_BASE).replace(/\/$/, '');
    this.timeoutMs = config.timeoutMs ?? 60_000;
    this.fetchImpl = config.fetchImpl ?? fetch;
  }

  async analyze(req: VisionRequest): Promise<VisionResponse> {
    const body = {
      contents: [
        {
          role: 'user',
          parts: [
            { text: req.prompt },
            { inline_data: { mime_type: req.mimeType, data: Buffer.from(req.image).toString('base64') } },
          ],
        },
      ],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: req.responseSchema,
        // Lowest randomness: the same photo should get the same number.
        temperature: 0,
        maxOutputTokens: 512,
      },
    };
    const res = await this.fetchImpl(`${this.baseUrl}/models/${this.modelId}:generateContent`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': this.apiKey },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!res.ok) {
      // The body can echo the request; keep only the status in the error.
      throw new Error(`Gemini returned HTTP ${res.status}`);
    }
    const reply = (await res.json()) as GeminiReply;
    const candidate = reply.candidates?.[0];
    const text = (candidate?.content?.parts ?? []).map((p) => p.text ?? '').join('');
    const u = reply.usageMetadata ?? {};
    return {
      text,
      usage: {
        inputTokens: u.promptTokenCount ?? 0,
        outputTokens: (u.candidatesTokenCount ?? 0) + (u.thoughtsTokenCount ?? 0),
      },
      finishReason: candidate?.finishReason ?? reply.promptFeedback?.blockReason,
    };
  }
}

export function mimeTypeFor(fileName: string): string | null {
  const ext = fileName.toLowerCase().split('.').pop();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    default:
      return null;
  }
}
