import { createHash } from 'node:crypto';
import type { DocumentReference } from 'firebase-admin/firestore';
import { beforeAll, describe, expect, it } from 'vitest';
import { createAgentToken, MAX_ACTIVE_TOKENS, randomBase62, revokeAgentToken, TOKEN_PATTERN } from '../src/agentTokens';
import { adminDb, newUid, requireEmulator, testDeps } from './helpers';

beforeAll(() => requireEmulator());

const NOW = new Date('2026-11-18T18:00:00Z');

/** Every field of every document under `ref`, as one string. */
async function dumpTree(ref: DocumentReference): Promise<string> {
  const parts: string[] = [];
  const snap = await ref.get();
  if (snap.exists) parts.push(JSON.stringify(snap.data()));
  for (const col of await ref.listCollections()) {
    for (const doc of (await col.get()).docs) parts.push(await dumpTree(doc.ref));
  }
  return parts.join('\n');
}

describe('randomBase62', () => {
  it('gives the requested length from the base62 alphabet', () => {
    const s = randomBase62(4000);
    expect(s).toHaveLength(4000);
    expect(s).toMatch(/^[A-Za-z0-9]+$/);
    // All 62 characters show up in 4000 draws.
    expect(new Set(s).size).toBe(62);
  });
});

describe('createAgentToken', () => {
  it('returns the token once and stores only its SHA-256 hash', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('tok');
    const out = await createAgentToken(deps, uid, { name: 'Claude', scopes: ['read:stats', 'read:profile', 'read:stats'] });

    expect(out.token).toMatch(TOKEN_PATTERN);
    expect(out.token).toHaveLength('pgym_pat_'.length + 40);
    expect(out.prefix).toBe(out.token.slice(0, 17));
    expect(out.scopes).toEqual(['read:profile', 'read:stats']);
    expect(out.createdAt).toBe(NOW.toISOString());
    expect(out.expiresAt).toBe(new Date(NOW.getTime() + 90 * 86_400_000).toISOString());

    const doc = (await adminDb().doc(`users/${uid}/agentTokens/${out.tokenId}`).get()).data()!;
    expect(doc.tokenHash).toBe(createHash('sha256').update(out.token).digest('hex'));
    expect(doc.scopes).toEqual(['read:profile', 'read:stats']);
    expect(doc.revokedAt).toBeNull();
    expect(doc.lastUsedAt).toBeNull();

    // The raw token, and its secret part, appear nowhere in the user's documents.
    const tree = await dumpTree(adminDb().doc(`users/${uid}`));
    expect(tree).toContain(doc.tokenHash);
    expect(tree).not.toContain(out.token);
    expect(tree).not.toContain(out.token.slice(17));
  });

  it('makes a token with no expiry when expiresInDays is null', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('tok');
    const out = await createAgentToken(deps, uid, { name: 'Script', scopes: ['read:sessions'], expiresInDays: null });
    expect(out.expiresAt).toBeNull();
    const doc = (await adminDb().doc(`users/${uid}/agentTokens/${out.tokenId}`).get()).data()!;
    expect(doc.expiresAt).toBeNull();
  });

  it('gives two calls two different tokens', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('tok');
    const a = await createAgentToken(deps, uid, { name: 'A', scopes: ['read:stats'] });
    const b = await createAgentToken(deps, uid, { name: 'B', scopes: ['read:stats'] });
    expect(a.token).not.toBe(b.token);
    expect(a.tokenId).not.toBe(b.tokenId);
  });

  it('rejects a caller who is not signed in', async () => {
    await expect(createAgentToken(testDeps(), undefined, { name: 'x', scopes: ['read:stats'] })).rejects.toMatchObject({
      code: 'unauthenticated',
    });
  });

  it.each([
    [{ name: '', scopes: ['read:stats'] }],
    [{ name: 'x', scopes: [] }],
    [{ name: 'x', scopes: ['write:sessions'] }],
    [{ name: 'x', scopes: ['read:stats'], expiresInDays: 0 }],
    [{ name: 'x', scopes: ['read:stats'], expiresInDays: 1.5 }],
    [{ name: 'x', scopes: ['read:stats'], extra: true }],
    [null],
  ])('rejects bad input %j', async (input) => {
    await expect(createAgentToken(testDeps(), newUid('tok'), input)).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it(`stops at ${MAX_ACTIVE_TOKENS} active tokens, and a revoked one frees a slot`, async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('tok');
    const made = [];
    for (let i = 0; i < MAX_ACTIVE_TOKENS; i++) made.push(await createAgentToken(deps, uid, { name: `t${i}`, scopes: ['read:stats'] }));
    await expect(createAgentToken(deps, uid, { name: 'one more', scopes: ['read:stats'] })).rejects.toMatchObject({
      code: 'resource-exhausted',
    });
    await revokeAgentToken(deps, uid, { tokenId: made[0].tokenId });
    await expect(createAgentToken(deps, uid, { name: 'one more', scopes: ['read:stats'] })).resolves.toBeTruthy();
  });
});

describe('revokeAgentToken', () => {
  it('marks the token revoked, and a second call keeps the first time', async () => {
    let now = NOW;
    const deps = testDeps({ now: () => now });
    const uid = newUid('tok');
    const { tokenId } = await createAgentToken(deps, uid, { name: 'x', scopes: ['read:stats'] });
    const first = await revokeAgentToken(deps, uid, { tokenId });
    expect(first.revokedAt).toBe(NOW.toISOString());
    now = new Date(NOW.getTime() + 60_000);
    const second = await revokeAgentToken(deps, uid, { tokenId });
    expect(second.revokedAt).toBe(NOW.toISOString());
  });

  it("cannot revoke another user's token", async () => {
    const deps = testDeps({ now: () => NOW });
    const a = newUid('a');
    const b = newUid('b');
    const { tokenId } = await createAgentToken(deps, a, { name: 'x', scopes: ['read:stats'] });
    await expect(revokeAgentToken(deps, b, { tokenId })).rejects.toMatchObject({ code: 'not-found' });
    const doc = (await adminDb().doc(`users/${a}/agentTokens/${tokenId}`).get()).data()!;
    expect(doc.revokedAt).toBeNull();
  });

  it('rejects a malformed tokenId', async () => {
    await expect(revokeAgentToken(testDeps(), newUid('tok'), { tokenId: '../x' })).rejects.toMatchObject({ code: 'invalid-argument' });
    await expect(revokeAgentToken(testDeps(), newUid('tok'), {})).rejects.toMatchObject({ code: 'invalid-argument' });
  });
});
