import { HttpsError } from './errors';

export const PHYSIQUE_PROMPT_VERSION = 'physique-seven-v1';
export const PHYSIQUE_KEYS = [
  'shoulderWaist', 'waistHeight', 'torsoDelt', 'symmetryAlignment', 'torsoCoreDefinition', 'quadProportion',
] as const;
export const MAX_PHYSIQUE_JPEG_BYTES = 1_500_000;

export const PHYSIQUE_PROMPT = `Analyze one consenting adult's full-body gym photo. Return only a JSON object with usable (boolean), dimensions (object), overall (integer), coaching (string), encouragement (string). The dimensions object must contain six integer scores from 0 to 100: shoulderWaist, waistHeight, torsoDelt, symmetryAlignment, torsoCoreDefinition, quadProportion. Score overall visible fitness and muscle development separately from 0 to 100. These are visual estimates, not measured ratios. Use visible shoulder and waist width, torso and shoulder contour, left/right silhouette and landmarks, upper torso and core edges, and thigh contour relative to hip and knee. If the full body is not visible, there is more than one person, or clothing, pose, framing or light makes any dimension unreliable, return usable false. Never infer body fat, visceral fat, metabolic health, injury risk, gender, identity, attractiveness, or a diagnosis. Do not claim knowledge of prior sessions. Coaching must have exactly three short positive sentences with specific training or photo-consistency guidance. Encouragement must be one separate positive sentence. No body shaming, diet, calories, weight loss or medical advice. The same photo should produce similar scores.`;

export interface PhysiqueResult {
  score: number;
  dimensions: Record<(typeof PHYSIQUE_KEYS)[number], number>;
  tip: string;
  encouragement: string;
}

export function parsePhysique(raw: string): PhysiqueResult | null {
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch { return null; }
  if (typeof parsed !== 'object' || parsed === null) return null;
  const result = parsed as { usable?: unknown; dimensions?: Record<string, unknown>; overall?: unknown; coaching?: unknown; encouragement?: unknown };
  if (result.usable !== true || typeof result.overall !== 'number' || !Number.isInteger(result.overall) || result.overall < 0 || result.overall > 100) return null;
  const dimensions = {} as PhysiqueResult['dimensions'];
  for (const key of PHYSIQUE_KEYS) {
    const value = result.dimensions?.[key];
    if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value > 100) return null;
    dimensions[key] = value;
  }
  const tip = typeof result.coaching === 'string' ? result.coaching.trim().replace(/\s+/g, ' ') : '';
  const encouragement = typeof result.encouragement === 'string' ? result.encouragement.trim().replace(/\s+/g, ' ') : '';
  const sentenceCount = (text: string) => (text.match(/[.!?](?=\s|$)/g) || []).length;
  if (!tip || tip.length > 600 || sentenceCount(tip) !== 3 || !encouragement || encouragement.length > 180 || sentenceCount(encouragement) !== 1) return null;
  if (/body fat|visceral|metabolic|injur|diagnos|weight loss|calori|diet/i.test(`${tip} ${encouragement}`)) return null;
  return { score: result.overall, dimensions, tip, encouragement };
}

export interface PhysiqueProvider {
  analyze(jpeg: Uint8Array): Promise<string>;
}

export class TogetherPhysiqueProvider implements PhysiqueProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model = process.env.TOGETHER_MODEL || 'Qwen/Qwen3-VL-8B-Instruct',
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async analyze(jpeg: Uint8Array): Promise<string> {
    if (!this.apiKey) throw new HttpsError('unavailable', 'Photo analysis is temporarily unavailable.');
    const response = await this.fetchImpl('https://api.together.xyz/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        temperature: 0,
        max_tokens: 800,
        messages: [{ role: 'user', content: [
          { type: 'text', text: PHYSIQUE_PROMPT },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${Buffer.from(jpeg).toString('base64')}` } },
        ] }],
      }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new HttpsError('unavailable', 'Photo analysis is temporarily unavailable.');
    const payload = await response.json() as { choices?: Array<{ message?: { content?: unknown } }> };
    const content = payload.choices?.[0]?.message?.content;
    if (typeof content !== 'string') throw new HttpsError('unavailable', 'Photo analysis is temporarily unavailable.');
    return content.trim();
  }
}

export async function scoreJpeg(provider: PhysiqueProvider, jpeg: Uint8Array): Promise<PhysiqueResult> {
  if (jpeg.byteLength < 4 || jpeg.byteLength > MAX_PHYSIQUE_JPEG_BYTES || jpeg[0] !== 0xff || jpeg[1] !== 0xd8 || jpeg.at(-2) !== 0xff || jpeg.at(-1) !== 0xd9) {
    throw new HttpsError('invalid-argument', 'Send a reduced JPEG under 1.5 MB.');
  }
  const parsed = parsePhysique(await provider.analyze(jpeg));
  if (!parsed) throw new HttpsError('failed-precondition', 'This photo could not be scored. Try a full-body photo in even light.');
  return parsed;
}
