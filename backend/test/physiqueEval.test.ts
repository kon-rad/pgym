import { describe, expect, it } from 'vitest';
import { costUsd, formatReport, runEval, summarize, type EvalPhoto } from '../src/physiqueEval';
import { FakeVisionModel } from './physiqueFakes';

const photo = (name: string): EvalPhoto => ({ name, mimeType: 'image/jpeg', bytes: new Uint8Array(10) });
const scored = (score: number) => ({ usable: true, refusedReason: null, score, tip: 'Add rows.' });

describe('physique eval', () => {
  it('scores each photo N times and reports mean, spread and cost per analysis', async () => {
    const model = new FakeVisionModel().reply(
      scored(60), scored(62), scored(64), scored(60), scored(64),
      scored(80), { usable: false, refusedReason: 'unreadable', score: null, tip: null }, scored(84), 'garbage', new Error('HTTP 503'),
    );
    const report = await runEval({
      model,
      photos: [photo('a.jpg'), photo('b.jpg')],
      runs: 5,
      prices: { inputPerMillion: 0.3, outputPerMillion: 2.5 },
    });
    expect(model.calls).toHaveLength(10);

    const [a, b] = report.photos;
    expect(a).toMatchObject({ name: 'a.jpg', scored: 5, mean: 62, min: 60, max: 64, range: 4 });
    expect(a.stdDev).toBeCloseTo(1.789, 3);
    expect(b).toMatchObject({ scored: 2, mean: 82, range: 4, refusals: { unreadable: 1, failure: 1, error: 1 } });

    // Fake usage: 1290 input and 60 output tokens per call -> (1290 * 0.3 + 60 * 2.5) / 1e6
    const perCall = (1290 * 0.3 + 60 * 2.5) / 1_000_000;
    expect(costUsd({ inputTokens: 1290, outputTokens: 60 }, { inputPerMillion: 0.3, outputPerMillion: 2.5 })).toBeCloseTo(perCall, 12);
    expect(report.analyses).toBe(9); // the thrown call has no token counts
    expect(report.meanCostUsd).toBeCloseTo(perCall, 12);
    expect(report.worstRange).toBe(4);

    const text = formatReport(report);
    expect(text).toContain('model fake-vision-model');
    expect(text).toMatch(/a\.jpg\s+5\/5\s+62\.0\s+1\.79\s+60\s+64\s+4/);
    expect(text).toContain('$0.000537');
  });

  it('prints token counts and "price not set" without prices', async () => {
    const report = await runEval({ model: new FakeVisionModel(), photos: [photo('a.jpg')], runs: 2, prices: null });
    expect(report.meanCostUsd).toBeNull();
    const text = formatReport(report);
    expect(text).toContain('price not set');
    expect(text).toContain('input 1290, output 60');
  });

  it('a photo with no scored runs has no mean', () => {
    const s = summarize('x.jpg', [{ score: null, refusedReason: 'no_person', usage: null, error: null }], null);
    expect(s).toMatchObject({ scored: 0, mean: null, range: null, refusals: { no_person: 1 } });
  });
});
