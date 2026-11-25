import { describe, expect, it, vi } from 'vitest';
import { parsePhysique, PHYSIQUE_KEYS, scoreJpeg, TogetherPhysiqueProvider } from '../lib/server/physique';

const jpeg = new Uint8Array([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);
const dimensions = Object.fromEntries(PHYSIQUE_KEYS.map((key) => [key, 62]));
const valid = {
  usable: true, dimensions, overall: 68,
  coaching: 'Add two sets of rows next session. Keep your camera distance consistent. Train through a comfortable range of motion.',
  encouragement: 'You are showing up and building momentum.',
};

describe('seven photo scores', () => {
  it('accepts six bounded dimensions, overall score, coaching and encouragement', async () => {
    const provider = { analyze: vi.fn().mockResolvedValue(JSON.stringify(valid)) };
    await expect(scoreJpeg(provider, jpeg)).resolves.toEqual({ score: 68, dimensions, tip: valid.coaching, encouragement: valid.encouragement });
    expect(provider.analyze).toHaveBeenCalledWith(jpeg);
  });

  it('rejects invented, missing, unsafe and malformed values', () => {
    expect(parsePhysique(JSON.stringify({ ...valid, dimensions: { ...dimensions, quadProportion: 101 } }))).toBeNull();
    expect(parsePhysique(JSON.stringify({ ...valid, dimensions: { shoulderWaist: 62 } }))).toBeNull();
    expect(parsePhysique(JSON.stringify({ ...valid, coaching: 'Your metabolic health is excellent. Keep training. Stay consistent.' }))).toBeNull();
    expect(parsePhysique(JSON.stringify({ ...valid, coaching: 'Keep training.' }))).toBeNull();
    expect(parsePhysique('not json')).toBeNull();
  });

  it('requires a reduced JPEG and does not call the model on invalid input', async () => {
    const provider = { analyze: vi.fn() };
    await expect(scoreJpeg(provider, new Uint8Array([1, 2, 3]))).rejects.toMatchObject({ code: 'invalid-argument' });
    expect(provider.analyze).not.toHaveBeenCalled();
  });

  it('sends the photo only to the configured Together model', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify(valid) } }] }), { status: 200 }));
    const provider = new TogetherPhysiqueProvider('server-key', 'model-id', fetchMock);
    await expect(provider.analyze(jpeg)).resolves.toContain('"overall":68');
    expect(fetchMock.mock.calls[0][0]).toBe('https://api.together.xyz/v1/chat/completions');
  });
});
