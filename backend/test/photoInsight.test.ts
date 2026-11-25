import { describe, expect, it } from 'vitest';
import type { Firestore } from 'firebase-admin/firestore';
import { analyzePhotoInsight, INSIGHT_PROMPT, INSIGHT_SCHEMA } from '../src/photoInsight';
import type { VisionModel, VisionRequest } from '../src/visionModel';

class FakeModel implements VisionModel {
  readonly modelId = 'fake-flash';
  calls: VisionRequest[] = [];
  text = JSON.stringify({ insight: 'Keep the same framing next time to make changes easier to notice.' });
  async analyze(req: VisionRequest) {
    this.calls.push(req);
    return { text: this.text, usage: { inputTokens: 10, outputTokens: 8 } };
  }
}

function fakeDb(user: Record<string, unknown>) {
  const writes: unknown[] = [];
  return {
    writes,
    doc(path: string) {
      return {
        path,
        async get() { return { data: () => user }; },
      };
    },
    async runTransaction(fn: (tx: { get: () => Promise<{ get: () => number | undefined }>; set: (_r: unknown, v: unknown) => void }) => Promise<void>) {
      await fn({ get: async () => ({ get: () => undefined }), set: (_r, value) => writes.push(value) });
    },
  };
}

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64');
const log = { info: () => undefined, warn: () => undefined };

describe('transient photo insight', () => {
  it('sends bytes in memory and returns validated insight without persisting it', async () => {
    const db = fakeDb({ photoAnalysisConsent: true, birthYear: 1990 });
    const model = new FakeModel();
    const out = await analyzePhotoInsight(
      { db: db as unknown as Firestore, model, now: () => new Date('2026-11-25T00:00:00Z'), log },
      'u1',
      { consent: true, imageBase64: jpeg },
    );
    expect(out.insight).toContain('same framing');
    expect(model.calls[0]).toMatchObject({ prompt: INSIGHT_PROMPT, responseSchema: INSIGHT_SCHEMA, mimeType: 'image/jpeg' });
    expect(JSON.stringify(db.writes)).not.toContain(out.insight);
    expect(JSON.stringify(db.writes)).not.toContain(jpeg);
  });

  it('rejects missing consent, minors and unsafe output', async () => {
    const model = new FakeModel();
    const deps = (user: Record<string, unknown>) => ({
      db: fakeDb(user) as unknown as Firestore,
      model,
      now: () => new Date('2026-11-25T00:00:00Z'),
      log,
    });
    await expect(analyzePhotoInsight(deps({ photoAnalysisConsent: true, birthYear: 1990 }), 'u1', { imageBase64: jpeg })).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(analyzePhotoInsight(deps({ photoAnalysisConsent: true, birthYear: 2012 }), 'u1', { consent: true, imageBase64: jpeg })).rejects.toMatchObject({ code: 'permission-denied' });
    model.text = JSON.stringify({ insight: 'Your body fat looks unhealthy!' });
    await expect(analyzePhotoInsight(deps({ photoAnalysisConsent: true, birthYear: 1990 }), 'u1', { consent: true, imageBase64: jpeg })).rejects.toMatchObject({ code: 'internal' });
  });
});
