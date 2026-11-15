import { describe, expect, it } from 'vitest';

describe('index', () => {
  it('exports the six functions of card B1', async () => {
    process.env.GCLOUD_PROJECT ??= 'pgym-local';
    const mod = await import('../src/index');
    expect(Object.keys(mod).sort()).toEqual(
      ['createUploadUrls', 'deleteAccount', 'deleteSession', 'getPhotoUrls', 'rollWeek', 'stampSession'],
    );
  });
});
