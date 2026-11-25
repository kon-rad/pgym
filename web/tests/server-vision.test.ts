import { afterEach, describe, expect, it, vi } from 'vitest';
import { HttpsError } from '../lib/server/errors';
import { analyzeJpeg, TogetherVisionProvider, type VisionProvider } from '../lib/server/vision';
import { log } from '../lib/server/log';

const JPEG = new Uint8Array([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);

afterEach(() => vi.restoreAllMocks());

describe('transient Together vision', () => {
  it('returns one bounded safe insight without retaining the JPEG', async () => {
    const provider: VisionProvider = { analyze: vi.fn().mockResolvedValue('Keep your wrists stacked over your forearms during the press.') };
    await expect(analyzeJpeg(provider, JPEG)).resolves.toEqual({ insight: 'Keep your wrists stacked over your forearms during the press.' });
    expect(provider.analyze).toHaveBeenCalledWith(JPEG);
  });

  it('maps refusal, provider errors, unsafe output, and body limits', async () => {
    await expect(analyzeJpeg({ analyze: async () => 'REFUSE' }, JPEG)).rejects.toMatchObject({ code: 'failed-precondition' });
    await expect(analyzeJpeg({ analyze: async () => { throw new Error('offline'); } }, JPEG)).rejects.toThrow('offline');
    await expect(analyzeJpeg({ analyze: async () => 'This diagnoses an injury.' }, JPEG)).rejects.toMatchObject({ code: 'internal' });
    await expect(analyzeJpeg({ analyze: async () => 'ok' }, new Uint8Array(1_500_001))).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(analyzeJpeg({ analyze: async () => 'ok' }, new Uint8Array([1, 2, 3]))).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('uses the OpenAI-compatible endpoint and turns upstream failure into a redacted error', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('no', { status: 503 }));
    const provider = new TogetherVisionProvider('secret-value', 'model-id', fetchMock);
    await expect(provider.analyze(JPEG)).rejects.toEqual(new HttpsError('internal', 'The insight provider is temporarily unavailable.'));
    const init = fetchMock.mock.calls[0][1] as RequestInit;
    expect(fetchMock.mock.calls[0][0]).toBe('https://api.together.xyz/v1/chat/completions');
    expect(init.headers).toMatchObject({ Authorization: 'Bearer secret-value' });
  });
});

describe('structured logging', () => {
  it('never writes secrets, image data, request bodies, or model output', () => {
    const spy = vi.spyOn(console, 'info').mockImplementation(() => undefined);
    log.info('test', { authorization: 'Bearer secret', photo: 'base64', body: 'raw', output: 'private', uid: 'safe' });
    const line = spy.mock.calls[0][0] as string;
    expect(line).not.toContain('secret');
    expect(line).not.toContain('base64');
    expect(line).not.toContain('private');
    expect(JSON.parse(line)).toMatchObject({ event: 'test', uid: 'safe', authorization: '[REDACTED]', photo: '[REDACTED]' });
  });
});
