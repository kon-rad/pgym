import { describe, expect, it } from 'vitest';
import { PHYSIQUE_PROMPT, PHYSIQUE_RESPONSE_SCHEMA } from '../src/physiquePrompt';
import { GeminiClient, mimeTypeFor } from '../src/visionModel';

// fetch is replaced in every test: nothing here reaches the network.
function fakeFetch(status: number, body: unknown) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const impl = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  }) as unknown as typeof fetch;
  return { calls, impl };
}

const request = { prompt: PHYSIQUE_PROMPT, responseSchema: PHYSIQUE_RESPONSE_SCHEMA, image: new Uint8Array([1, 2, 3]), mimeType: 'image/jpeg' };

describe('GeminiClient', () => {
  it('posts the prompt, the image and the JSON schema, with the key in a header, and reads text and tokens', async () => {
    const f = fakeFetch(200, {
      candidates: [{ content: { parts: [{ text: '{"usable":true,' }, { text: '"score":61}' }] }, finishReason: 'STOP' }],
      usageMetadata: { promptTokenCount: 1300, candidatesTokenCount: 40, thoughtsTokenCount: 25 },
    });
    const client = new GeminiClient({ apiKey: 'test-key', modelId: 'test-model-1', fetchImpl: f.impl });
    const res = await client.analyze(request);

    expect(res).toEqual({ text: '{"usable":true,"score":61}', usage: { inputTokens: 1300, outputTokens: 65 }, finishReason: 'STOP' });
    expect(f.calls).toHaveLength(1);
    const { url, init } = f.calls[0];
    expect(url).toBe('https://generativelanguage.googleapis.com/v1beta/models/test-model-1:generateContent');
    expect(url).not.toContain('test-key');
    expect((init.headers as Record<string, string>)['x-goog-api-key']).toBe('test-key');
    const body = JSON.parse(String(init.body));
    expect(body.contents[0].parts[0].text).toBe(PHYSIQUE_PROMPT);
    expect(body.contents[0].parts[1].inline_data).toEqual({ mime_type: 'image/jpeg', data: 'AQID' });
    expect(body.generationConfig).toMatchObject({ responseMimeType: 'application/json', temperature: 0 });
    expect(body.generationConfig.responseSchema).toEqual(PHYSIQUE_RESPONSE_SCHEMA);
  });

  it('a blocked reply returns empty text, which the parser treats as malformed', async () => {
    const f = fakeFetch(200, { promptFeedback: { blockReason: 'SAFETY' }, usageMetadata: { promptTokenCount: 1300 } });
    const res = await new GeminiClient({ apiKey: 'k', modelId: 'm', fetchImpl: f.impl }).analyze(request);
    expect(res).toEqual({ text: '', usage: { inputTokens: 1300, outputTokens: 0 }, finishReason: 'SAFETY' });
  });

  it('an HTTP error throws with the status only', async () => {
    const f = fakeFetch(429, { error: { message: 'quota for key test-key' } });
    await expect(new GeminiClient({ apiKey: 'test-key', modelId: 'm', fetchImpl: f.impl }).analyze(request)).rejects.toThrow(
      /^Gemini returned HTTP 429$/,
    );
  });

  it('refuses to start without a key or with a malformed model ID', () => {
    expect(() => new GeminiClient({ apiKey: '', modelId: 'm' })).toThrow();
    expect(() => new GeminiClient({ apiKey: 'k', modelId: '' })).toThrow();
    expect(() => new GeminiClient({ apiKey: 'k', modelId: '../x' })).toThrow();
  });

  it('mimeTypeFor', () => {
    expect(['a.JPG', 'b.jpeg', 'c.png', 'd.webp', 'e.heic', 'f.txt'].map(mimeTypeFor)).toEqual([
      'image/jpeg',
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      null,
    ]);
  });
});
