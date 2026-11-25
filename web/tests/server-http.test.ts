import { describe, expect, it, vi } from 'vitest';

vi.mock('../lib/server/firebase', () => ({
  services: () => ({ auth: { verifyIdToken: vi.fn() } }),
}));
vi.mock('../lib/server/rollover', () => ({ triggerLazyWeekRollover: vi.fn() }));

import { GET as health } from '../app/api/health/route';
import { jsonBody, uidFromRequest } from '../lib/server/http';

describe('HTTP boundary', () => {
  it('rejects a request without a Firebase ID token', async () => {
    await expect(uidFromRequest(new Request('http://local/api/sessions/stamp'))).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  it('enforces JSON body size by header and actual bytes', async () => {
    const declared = new Request('http://local', { method: 'POST', headers: { 'content-length': '101' }, body: '{}' });
    await expect(jsonBody(declared, 100)).rejects.toMatchObject({ code: 'invalid-argument' });
    const actual = new Request('http://local', { method: 'POST', body: JSON.stringify({ value: 'x'.repeat(100) }) });
    await expect(jsonBody(actual, 50)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('reports health and exact running revision', async () => {
    process.env.APP_REVISION = 'abc1234';
    const response = health();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ status: 'ok', revision: 'abc1234' });
  });
});
