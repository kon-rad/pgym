import { beforeEach, describe, expect, it, vi } from 'vitest';

const { stamp, removeSession, removeAccount, createToken, revokeToken, verify, agent, requirePro, userGet, analyzeJpeg } = vi.hoisted(() => ({
  stamp: vi.fn(),
  removeSession: vi.fn(),
  removeAccount: vi.fn(),
  createToken: vi.fn(),
  revokeToken: vi.fn(),
  verify: vi.fn(),
  agent: vi.fn(),
  requirePro: vi.fn(),
  userGet: vi.fn(),
  analyzeJpeg: vi.fn(),
}));

vi.mock('../lib/server/domain/handlers', () => ({ stampSession: stamp, deleteSession: removeSession, deleteAccount: removeAccount }));
vi.mock('../lib/server/domain/agentTokens', () => ({ createAgentToken: createToken, revokeAgentToken: revokeToken }));
vi.mock('../lib/server/domain/api', () => ({ handleApi: agent }));
vi.mock('../lib/server/firebase', () => ({ services: () => ({
  auth: { verifyIdToken: verify },
  db: { doc: () => ({ get: userGet }) },
  marker: 'deps',
}) }));
vi.mock('../lib/server/rollover', () => ({ triggerLazyWeekRollover: vi.fn() }));
vi.mock('../lib/server/revenuecat', () => ({ requireProEntitlement: requirePro }));
vi.mock('../lib/server/rate-limit', () => ({ enforceRateLimit: vi.fn() }));
vi.mock('../lib/server/vision', () => ({
  MAX_JPEG_BYTES: 1_500_000,
  TogetherVisionProvider: class {},
  analyzeJpeg,
}));

import { POST as stampRoute } from '../app/api/sessions/stamp/route';
import { DELETE as deleteSessionRoute } from '../app/api/sessions/[id]/route';
import { DELETE as deleteAccountRoute } from '../app/api/account/route';
import { POST as createTokenRoute } from '../app/api/agent-tokens/route';
import { DELETE as revokeTokenRoute } from '../app/api/agent-tokens/[id]/route';
import { GET as agentRoute } from '../app/v1/[...path]/route';
import { POST as photoInsightRoute } from '../app/api/photo-insight/route';
import { HttpsError } from '../lib/server/errors';

const auth = { authorization: 'Bearer firebase-id-token', 'content-type': 'application/json' };

beforeEach(() => {
  vi.clearAllMocks();
  verify.mockResolvedValue({ uid: 'owner-a' });
  requirePro.mockResolvedValue(undefined);
  userGet.mockResolvedValue({ data: () => ({ photoInsightConsent: true, birthYear: 1990 }) });
  analyzeJpeg.mockResolvedValue({ insight: 'Keep your stance steady.' });
});

describe('authenticated operation routes', () => {
  it('stamps only as the verified owner and never accepts a body uid', async () => {
    stamp.mockResolvedValue({ proofNumber: 8 });
    const response = await stampRoute(new Request('http://local/api/sessions/stamp', { method: 'POST', headers: auth, body: JSON.stringify({ sessionId: 's1', uid: 'owner-b' }) }));
    expect(response.status).toBe(200);
    expect(stamp).toHaveBeenCalledWith(expect.objectContaining({ marker: 'deps' }), 'owner-a', expect.objectContaining({ sessionId: 's1', uid: 'owner-b' }));
  });

  it('deletes sessions and accounts under the verified owner', async () => {
    removeSession.mockResolvedValue({ deleted: true });
    removeAccount.mockResolvedValue({ deletedObjects: 0 });
    await deleteSessionRoute(new Request('http://local/api/sessions/s2', { method: 'DELETE', headers: auth }), { params: Promise.resolve({ id: 's2' }) });
    await deleteAccountRoute(new Request('http://local/api/account', { method: 'DELETE', headers: auth }));
    expect(removeSession).toHaveBeenCalledWith(expect.anything(), 'owner-a', { sessionId: 's2' });
    expect(removeAccount).toHaveBeenCalledWith(expect.anything(), 'owner-a');
  });

  it('creates and revokes hashed-token records through the owner-scoped domain', async () => {
    createToken.mockResolvedValue({ tokenId: 't1', token: 'shown-once' });
    revokeToken.mockResolvedValue({ tokenId: 't1' });
    const created = await createTokenRoute(new Request('http://local/api/agent-tokens', { method: 'POST', headers: auth, body: JSON.stringify({ name: 'Coach', scopes: ['read:stats'] }) }));
    await revokeTokenRoute(new Request('http://local/api/agent-tokens/t1', { method: 'DELETE', headers: auth }), { params: Promise.resolve({ id: 't1' }) });
    expect(created.status).toBe(201);
    expect(requirePro).toHaveBeenCalledTimes(2);
    expect(requirePro).toHaveBeenNthCalledWith(1, 'owner-a');
    expect(createToken).toHaveBeenCalledWith(expect.anything(), 'owner-a', expect.objectContaining({ name: 'Coach' }));
    expect(revokeToken).toHaveBeenCalledWith(expect.anything(), 'owner-a', { tokenId: 't1' });
  });

  it('rejects inactive Pro before token creation and maps provider failure to a service error', async () => {
    requirePro.mockRejectedValueOnce(new HttpsError('permission-denied', 'An active Pro entitlement is required.'));
    const inactive = await createTokenRoute(new Request('http://local/api/agent-tokens', { method: 'POST', headers: auth, body: '{}' }));
    expect(inactive.status).toBe(403);
    await expect(inactive.json()).resolves.toMatchObject({ error: { code: 'permission-denied' } });
    expect(createToken).not.toHaveBeenCalled();

    requirePro.mockRejectedValueOnce(new HttpsError('unavailable', 'Subscription verification is temporarily unavailable.'));
    const unavailable = await revokeTokenRoute(new Request('http://local/api/agent-tokens/t1', { method: 'DELETE', headers: auth }), { params: Promise.resolve({ id: 't1' }) });
    expect(unavailable.status).toBe(503);
    await expect(unavailable.json()).resolves.toMatchObject({ error: { code: 'unavailable' } });
    expect(revokeToken).not.toHaveBeenCalled();
  });

  it('does not consult RevenueCat for free stamping or account operations', async () => {
    stamp.mockResolvedValue({ proofNumber: 1 });
    removeAccount.mockResolvedValue({ deletedObjects: 0 });
    await stampRoute(new Request('http://local/api/sessions/stamp', { method: 'POST', headers: auth, body: JSON.stringify({ sessionId: 's1' }) }));
    await deleteAccountRoute(new Request('http://local/api/account', { method: 'DELETE', headers: auth }));
    expect(requirePro).not.toHaveBeenCalled();
  });

  it('accepts photo insight for active Pro and rejects inactive Pro before reading the photo', async () => {
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    const active = await photoInsightRoute(new Request('http://local/api/photo-insight', {
      method: 'POST', headers: { authorization: auth.authorization, 'content-type': 'image/jpeg' }, body: jpeg,
    }));
    expect(active.status).toBe(200);
    expect(analyzeJpeg).toHaveBeenCalledOnce();

    vi.clearAllMocks();
    verify.mockResolvedValue({ uid: 'owner-a' });
    requirePro.mockRejectedValue(new HttpsError('permission-denied', 'An active Pro entitlement is required.'));
    const inactive = await photoInsightRoute(new Request('http://local/api/photo-insight', {
      method: 'POST', headers: { authorization: auth.authorization, 'content-type': 'image/jpeg' }, body: jpeg,
    }));
    expect(inactive.status).toBe(403);
    expect(analyzeJpeg).not.toHaveBeenCalled();
  });
});

describe('read-only agent API route', () => {
  it('forwards only the bearer token and requested owner-isolated path to the proven domain handler', async () => {
    agent.mockResolvedValue({ status: 404, headers: { 'Content-Type': 'application/json' }, body: { error: { code: 'not_found' } } });
    const response = await agentRoute(new Request('http://local/v1/sessions/other-user-session', { headers: { authorization: 'Bearer pgym_pat_test' } }), { params: Promise.resolve({ path: ['sessions', 'other-user-session'] }) });
    expect(response.status).toBe(404);
    expect(agent).toHaveBeenCalledWith(expect.objectContaining({ marker: 'deps' }), expect.objectContaining({ method: 'GET', path: '/v1/sessions/other-user-session', headers: expect.objectContaining({ authorization: 'Bearer pgym_pat_test' }) }));
  });
});
