import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { Logger } from './handlers';
import type { VisionModel } from './visionModel';

export const INSIGHT_MODEL_ID = 'gemini-2.5-flash';
export const INSIGHT_MAX_BYTES = 4 * 1024 * 1024;
export const INSIGHT_DAILY_LIMIT = 3;
export const INSIGHT_MAX_CHARS = 160;
export const INSIGHT_PROMPT_VERSION = 'training-insight-v1';

export const INSIGHT_SCHEMA = {
  type: 'OBJECT',
  properties: {
    insight: { type: 'STRING', description: 'One positive, gender-neutral training suggestion, at most 160 characters.' },
  },
  required: ['insight'],
} as const;

export const INSIGHT_PROMPT = `Return JSON with one "insight". It must be a concise, positive, gender-neutral training suggestion grounded only in visible framing or muscle-group balance. Never infer workout performance, health, body composition, age, identity, attractiveness, diagnosis, or medical facts. Never mention weight loss, diet, body fat, guilt, or certainty. Use 160 characters or fewer.`;

export interface PhotoInsightDeps {
  db: Firestore;
  model: VisionModel;
  now: () => Date;
  log: Logger;
}

function adult(birthYear: unknown, now: Date): boolean {
  return typeof birthYear === 'number' && Number.isInteger(birthYear) && now.getUTCFullYear() - birthYear >= 18;
}

function safeInsight(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const text = value.trim().replace(/\s+/g, ' ');
  if (!text || Array.from(text).length > INSIGHT_MAX_CHARS || /!|body fat|weight loss|diagnos|medical|health/i.test(text)) return null;
  return text;
}

/** Transient inference: the image and returned insight are never written to Firestore or logs. */
export async function analyzePhotoInsight(
  deps: PhotoInsightDeps,
  uid: string | undefined,
  data: unknown,
): Promise<{ insight: string; model: string; promptVersion: string }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const input = data as Record<string, unknown> | null;
  if (input?.consent !== true) throw new HttpsError('failed-precondition', 'Photo analysis consent is required.');
  if (typeof input.imageBase64 !== 'string') throw new HttpsError('invalid-argument', 'A JPEG is required.');
  const image = Buffer.from(input.imageBase64, 'base64');
  if (image.length < 4 || image.length > INSIGHT_MAX_BYTES || image[0] !== 0xff || image[1] !== 0xd8) {
    throw new HttpsError('invalid-argument', 'The image must be a reduced JPEG under 4 MB.');
  }
  const user = (await deps.db.doc(`users/${uid}`).get()).data();
  if ((user?.photoAnalysisConsent !== true && user?.physiqueConsent !== true) || !adult(user.birthYear, deps.now())) {
    throw new HttpsError('permission-denied', 'Photo analysis is unavailable.');
  }

  const day = deps.now().toISOString().slice(0, 10);
  const rateRef = deps.db.doc(`users/${uid}/privateRateLimits/photoInsight-${day}`);
  await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(rateRef);
    const count = typeof snap.get('count') === 'number' ? snap.get('count') : 0;
    if (count >= INSIGHT_DAILY_LIMIT) throw new HttpsError('resource-exhausted', 'Try photo analysis again tomorrow.');
    tx.set(rateRef, { count: count + 1, updatedAt: Timestamp.fromDate(deps.now()) });
  });

  const response = await deps.model.analyze({ prompt: INSIGHT_PROMPT, responseSchema: INSIGHT_SCHEMA, image, mimeType: 'image/jpeg' });
  let parsed: unknown;
  try { parsed = JSON.parse(response.text); } catch { throw new HttpsError('internal', 'Photo analysis was unavailable.'); }
  const insight = safeInsight((parsed as { insight?: unknown } | null)?.insight);
  if (!insight) throw new HttpsError('internal', 'Photo analysis was unavailable.');
  deps.log.info('analyzePhotoInsight', {
    uid,
    model: deps.model.modelId,
    promptVersion: INSIGHT_PROMPT_VERSION,
    inputTokens: response.usage.inputTokens,
    outputTokens: response.usage.outputTokens,
  });
  return { insight, model: deps.model.modelId, promptVersion: INSIGHT_PROMPT_VERSION };
}
