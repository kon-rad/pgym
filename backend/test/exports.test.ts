import { describe, expect, it } from 'vitest';

describe('index', () => {
  it('exports the functions of cards B1, A1 and B2', async () => {
    process.env.GCLOUD_PROJECT ??= 'pgym-local';
    const mod = await import('../src/index');
    expect(Object.keys(mod).sort()).toEqual([
      'analyzePhysique',
      'api',
      'createAgentToken',
      'createUploadUrls',
      'deleteAccount',
      'deleteSession',
      'getPhotoUrls',
      'revokeAgentToken',
      'rollWeek',
      'stampSession',
    ]);
  });
});
