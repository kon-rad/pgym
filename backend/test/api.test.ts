import { Timestamp } from 'firebase-admin/firestore';
import { beforeAll, describe, expect, it } from 'vitest';
import { createAgentToken, revokeAgentToken } from '../src/agentTokens';
import { handleApi, type ApiResponse } from '../src/api';
import type { Scope } from '../src/apiSchemas';
import * as h from '../src/handlers';
import { adminDb, newUid, requireEmulator, testDeps } from './helpers';

beforeAll(() => requireEmulator());

const NOW = new Date('2026-11-18T18:00:00Z'); // Wednesday of 2026-W47
const ALL: Scope[] = ['read:profile', 'read:sessions', 'read:stats'];

type Deps = ReturnType<typeof testDeps>;

/** A test clock that can be moved forward. */
function clock(start = NOW) {
  let t = start.getTime();
  return { now: () => new Date(t), advance: (ms: number) => (t += ms) };
}

async function token(deps: Deps, uid: string, scopes: Scope[], expiresInDays?: number | null): Promise<string> {
  return (await createAgentToken(deps, uid, { name: 'test agent', scopes, ...(expiresInDays !== undefined ? { expiresInDays } : {}) })).token;
}

function get(deps: Deps, path: string, tok?: string, query: Record<string, unknown> = {}): Promise<ApiResponse> {
  return handleApi(deps, {
    method: 'GET',
    path,
    query,
    headers: tok === undefined ? {} : { authorization: `Bearer ${tok}` },
  });
}

function code(res: ApiResponse): string | undefined {
  return (res.body as { error?: { code?: string } }).error?.code;
}

async function seedUser(uid: string, fields: Record<string, unknown> = {}): Promise<void> {
  await adminDb().doc(`users/${uid}`).set({
    displayName: `Sam ${uid}`,
    email: `${uid}@example.com`,
    birthYear: 1990,
    units: 'kg',
    timezone: 'UTC',
    goalPerWeek: 3,
    gymDays: ['mon', 'wed', 'fri'],
    createdAt: Timestamp.fromDate(new Date('2026-11-01T00:00:00Z')),
    ...fields,
  });
}

const BENCH = {
  exerciseId: 'bench-press',
  name: 'Bench press',
  sets: [
    { n: 1, weight: 40, reps: 10, type: 'warmup', done: true },
    { n: 2, weight: 80, reps: 5, type: 'working', done: true },
    { n: 3, weight: 82.5, reps: 3, type: 'working', done: true },
    { n: 4, weight: 85, reps: 1, type: 'working', done: false },
  ],
};

async function seedSession(uid: string, id: string, startedAt: Date, fields: Record<string, unknown> = {}): Promise<void> {
  await adminDb().doc(`users/${uid}/sessions/${id}`).set({
    status: 'finished',
    routineId: 'push-a',
    routineName: 'Push A',
    startedAt: Timestamp.fromDate(startedAt),
    endedAt: Timestamp.fromDate(new Date(startedAt.getTime() + 50 * 60_000)),
    timezone: 'UTC',
    exercises: [BENCH],
    ...fields,
  });
}

/** A session stamped by the real stampSession handler. */
async function stamped(deps: Deps, uid: string, id: string, startedAt: Date, fields: Record<string, unknown> = {}): Promise<void> {
  await seedSession(uid, id, startedAt, fields);
  await h.stampSession(deps, uid, {
    sessionId: id,
    photoSHA256: 'a'.repeat(64),
    cardFormatVersion: 1,
    filter: 'iron',
    proofImageCreated: true,
  });
}

describe('agent API: authentication', () => {
  it('gives 401 invalid_token for a missing token', async () => {
    const res = await get(testDeps(), '/v1/me');
    expect(res.status).toBe(401);
    expect(code(res)).toBe('invalid_token');
    expect(res.headers['WWW-Authenticate']).toContain('Bearer');
  });

  it.each([
    ['not a bearer header', 'Basic abc'],
    ['wrong prefix', `Bearer ghp_${'a'.repeat(40)}`],
    ['too short', 'Bearer pgym_pat_abc'],
    ['bad characters', `Bearer pgym_pat_${'-'.repeat(40)}`],
    ['empty bearer', 'Bearer '],
  ])('gives 401 for a malformed token (%s)', async (_label, header) => {
    const res = await handleApi(testDeps(), { method: 'GET', path: '/v1/me', query: {}, headers: { authorization: header } });
    expect(res.status).toBe(401);
    expect(code(res)).toBe('invalid_token');
  });

  it('gives 401 for a well-formed token that does not exist', async () => {
    const res = await get(testDeps(), '/v1/me', `pgym_pat_${'A'.repeat(40)}`);
    expect(res.status).toBe(401);
    expect(code(res)).toBe('invalid_token');
  });

  it('gives 401 for a revoked token, at once', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('rev');
    await seedUser(uid);
    const created = await createAgentToken(deps, uid, { name: 'x', scopes: ['read:profile'] });
    expect((await get(deps, '/v1/me', created.token)).status).toBe(200);
    await revokeAgentToken(deps, uid, { tokenId: created.tokenId });
    const res = await get(deps, '/v1/me', created.token);
    expect(res.status).toBe(401);
    expect(code(res)).toBe('invalid_token');
    expect((res.body as { error: { message: string } }).error.message).toMatch(/revoked/);
  });

  it('gives 401 for an expired token', async () => {
    const c = clock();
    const deps = testDeps({ now: c.now });
    const uid = newUid('exp');
    await seedUser(uid);
    const tok = await token(deps, uid, ['read:profile'], 1);
    expect((await get(deps, '/v1/me', tok)).status).toBe(200);
    c.advance(24 * 60 * 60 * 1000);
    const res = await get(deps, '/v1/me', tok);
    expect(res.status).toBe(401);
    expect(code(res)).toBe('invalid_token');
    expect((res.body as { error: { message: string } }).error.message).toMatch(/expired/);
  });

  it('accepts a token with no expiry a year later', async () => {
    const c = clock();
    const deps = testDeps({ now: c.now });
    const uid = newUid('noexp');
    await seedUser(uid);
    const tok = await token(deps, uid, ['read:profile'], null);
    c.advance(400 * 24 * 60 * 60 * 1000);
    expect((await get(deps, '/v1/me', tok)).status).toBe(200);
  });

  it('records lastUsedAt on each accepted request', async () => {
    const c = clock();
    const deps = testDeps({ now: c.now });
    const uid = newUid('used');
    await seedUser(uid);
    const created = await createAgentToken(deps, uid, { name: 'x', scopes: ['read:profile'] });
    c.advance(5_000);
    await get(deps, '/v1/me', created.token);
    const doc = (await adminDb().doc(`users/${uid}/agentTokens/${created.tokenId}`).get()).data()!;
    expect((doc.lastUsedAt as Timestamp).toDate().toISOString()).toBe(c.now().toISOString());
  });
});

describe('agent API: scopes', () => {
  it.each([
    ['/v1/me', 'read:profile'],
    ['/v1/stats', 'read:stats'],
    ['/v1/sessions', 'read:sessions'],
    ['/v1/sessions/s1', 'read:sessions'],
    ['/v1/exercises/bench-press/history', 'read:sessions'],
  ])('%s without %s gives 403 insufficient_scope', async (path, scope) => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('scope');
    await seedUser(uid);
    const tok = await token(deps, uid, ALL.filter((s) => s !== scope));
    const res = await get(deps, path, tok);
    expect(res.status).toBe(403);
    expect(res.body).toMatchObject({ error: { code: 'insufficient_scope', requiredScope: scope } });
  });
});

describe('agent API: isolation between users', () => {
  it("user A's token can never read user B's session", async () => {
    const deps = testDeps({ now: () => NOW });
    const a = newUid('a');
    const b = newUid('b');
    await seedUser(a);
    await seedUser(b);
    await stamped(deps, b, 'b-session', new Date(NOW.getTime() - 3 * 3600_000));
    const tokA = await token(deps, a, ALL);
    const tokB = await token(deps, b, ALL);

    // B can read it.
    expect((await get(deps, '/v1/sessions/b-session', tokB)).status).toBe(200);

    // A cannot, by any route.
    for (const path of ['/v1/sessions/b-session', '/v1/sessions/b-session/card']) {
      const res = await get(deps, path, tokA);
      expect(res.status).toBe(404);
      expect(code(res)).toBe('not_found');
    }
    const list = await get(deps, '/v1/sessions', tokA);
    expect(list.status).toBe(200);
    expect((list.body as { sessions: unknown[] }).sessions).toEqual([]);
    expect((await get(deps, '/v1/exercises/bench-press/history', tokA)).status).toBe(404);
    const stats = (await get(deps, '/v1/stats', tokA)).body as { proofCount: number; totalVolumeKg: number };
    expect(stats.proofCount).toBe(0);
    expect(stats.totalVolumeKg).toBe(0);
    expect(((await get(deps, '/v1/me', tokA)).body as { displayName: string }).displayName).toBe(`Sam ${a}`);
  });
});

describe('agent API: rate limit', () => {
  it('gives 429 on the 61st request in a minute, then recovers', async () => {
    const c = clock();
    const deps = testDeps({ now: c.now });
    const uid = newUid('rate');
    await seedUser(uid);
    const created = await createAgentToken(deps, uid, { name: 'x', scopes: ['read:profile'] });
    for (let i = 1; i <= 60; i++) {
      const res = await get(deps, '/v1/me', created.token);
      expect(res.status, `request ${i}`).toBe(200);
      expect(res.headers['X-RateLimit-Remaining']).toBe(String(60 - i));
      c.advance(500); // 60 requests over 30 seconds
    }
    const limited = await get(deps, '/v1/me', created.token);
    expect(limited.status).toBe(429);
    expect(code(limited)).toBe('rate_limited');
    expect(Number(limited.headers['Retry-After'])).toBe(30);

    // Another token of the same user has its own budget.
    const other = await token(deps, uid, ['read:profile']);
    expect((await get(deps, '/v1/me', other)).status).toBe(200);

    c.advance(30_000);
    expect((await get(deps, '/v1/me', created.token)).status).toBe(200);
  });
});

describe('agent API: endpoints', () => {
  it('GET /v1/me returns the profile and nothing private', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('me');
    await seedUser(uid, { gymDays: [1, 3, 5, 'sat'], units: 'lb', timezone: 'Europe/London', physiqueConsent: true });
    const res = await get(deps, '/v1/me', await token(deps, uid, ['read:profile']));
    expect(res.status).toBe(200);
    expect(res.headers['Content-Type']).toMatch(/application\/json/);
    expect(res.body).toEqual({
      displayName: `Sam ${uid}`,
      units: 'lb',
      timezone: 'Europe/London',
      goalPerWeek: 3,
      gymDays: ['mon', 'wed', 'fri', 'sat'],
    });
  });

  it('GET /v1/stats returns streak, this week and total weight', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('stats');
    await seedUser(uid);
    await stamped(deps, uid, 's1', new Date('2026-11-16T18:00:00Z'));
    await stamped(deps, uid, 's2', new Date('2026-11-17T18:00:00Z'));
    const res = await get(deps, '/v1/stats', await token(deps, uid, ['read:stats']));
    expect(res.status).toBe(200);
    // Per session: 80 x 5 + 82.5 x 3 = 647.5 kg (the warm-up and the undone set do not count).
    expect(res.body).toEqual({
      streakWeeks: 0,
      longestStreak: 0,
      passWeeks: 0,
      proofCount: 2,
      thisWeek: { weekKey: '2026-W47', sessions: 2, goal: 3 },
      totalVolumeKg: 1295,
    });
  });

  it('GET /v1/sessions pages at 50, newest first, with a cursor', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('page');
    await seedUser(uid);
    const writes = [];
    for (let i = 0; i < 55; i++) {
      writes.push(seedSession(uid, `s${String(i).padStart(2, '0')}`, new Date(NOW.getTime() - (i + 1) * 3600_000)));
    }
    writes.push(seedSession(uid, 'draft', new Date(NOW.getTime() - 1000), { status: 'draft' }));
    await Promise.all(writes);
    const tok = await token(deps, uid, ['read:sessions']);

    const p1 = await get(deps, '/v1/sessions', tok);
    expect(p1.status).toBe(200);
    const b1 = p1.body as { sessions: Array<{ id: string; status: string; setCount: number; totalVolumeKg: number }>; nextCursor: string };
    expect(b1.sessions).toHaveLength(50);
    expect(b1.sessions[0].id).toBe('s00');
    expect(b1.sessions[49].id).toBe('s49');
    expect(b1.sessions.some((s) => s.id === 'draft')).toBe(false);
    expect(b1.sessions[0]).toMatchObject({ status: 'finished', setCount: 2, totalVolumeKg: 647.5 });
    expect(b1.nextCursor).toEqual(expect.any(String));

    const p2 = await get(deps, '/v1/sessions', tok, { cursor: b1.nextCursor });
    const b2 = p2.body as { sessions: Array<{ id: string }>; nextCursor: string | null };
    expect(b2.sessions.map((s) => s.id)).toEqual(['s50', 's51', 's52', 's53', 's54']);
    expect(b2.nextCursor).toBeNull();
  });

  it('GET /v1/sessions filters by from and to in the owner time zone, both inclusive', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('range');
    await seedUser(uid, { timezone: 'America/New_York' });
    // 2026-11-16 in New York runs 05:00Z on the 16th to 05:00Z on the 17th.
    await seedSession(uid, 'before', new Date('2026-11-16T04:59:00Z'));
    await seedSession(uid, 'first', new Date('2026-11-16T05:00:00Z'));
    await seedSession(uid, 'last', new Date('2026-11-17T04:59:00Z'));
    await seedSession(uid, 'after', new Date('2026-11-17T05:00:00Z'));
    const tok = await token(deps, uid, ['read:sessions']);
    const res = await get(deps, '/v1/sessions', tok, { from: '2026-11-16', to: '2026-11-16' });
    expect((res.body as { sessions: Array<{ id: string }> }).sessions.map((s) => s.id)).toEqual(['last', 'first']);
  });

  it.each([
    [{ from: '16-11-2026' }],
    [{ to: '2026-13-01' }],
    [{ from: '2026-11-17', to: '2026-11-16' }],
    [{ cursor: 'not-a-cursor' }],
    [{ from: ['2026-11-01', '2026-11-02'] }],
  ])('GET /v1/sessions rejects %j with 400 invalid_request', async (query) => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('bad');
    await seedUser(uid);
    const res = await get(deps, '/v1/sessions', await token(deps, uid, ['read:sessions']), query);
    expect(res.status).toBe(400);
    expect(code(res)).toBe('invalid_request');
  });

  it('GET /v1/sessions/{id} returns every set, in kilograms', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('one');
    await seedUser(uid);
    await stamped(deps, uid, 's1', new Date(NOW.getTime() - 2 * 3600_000));
    const res = await get(deps, '/v1/sessions/s1', await token(deps, uid, ['read:sessions']));
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      id: 's1',
      status: 'stamped',
      routineId: 'push-a',
      routineName: 'Push A',
      proofNumber: 1,
      stampedAt: NOW.toISOString(),
      weekKey: '2026-W47',
      setCount: 2,
      totalVolumeKg: 647.5,
      newBests: [],
      exercises: [
        {
          exerciseId: 'bench-press',
          name: 'Bench press',
          sets: [
            { n: 1, type: 'warmup', weightKg: 40, reps: 10, done: true, rpe: null },
            { n: 2, type: 'working', weightKg: 80, reps: 5, done: true, rpe: null },
            { n: 3, type: 'working', weightKg: 82.5, reps: 3, done: true, rpe: null },
            { n: 4, type: 'working', weightKg: 85, reps: 1, done: false, rpe: null },
          ],
        },
      ],
    });
    // Storage keys are internal.
    expect(JSON.stringify(res.body)).not.toContain('photo.jpg');
  });

  it('GET /v1/sessions/{id} gives 404 for a draft, a missing session and a bad id', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('miss');
    await seedUser(uid);
    await seedSession(uid, 'd1', new Date(NOW.getTime() - 3600_000), { status: 'draft' });
    const tok = await token(deps, uid, ['read:sessions']);
    expect((await get(deps, '/v1/sessions/d1', tok)).status).toBe(404);
    expect((await get(deps, '/v1/sessions/nope', tok)).status).toBe(404);
    const bad = await get(deps, '/v1/sessions/a.b', tok);
    expect(bad.status).toBe(400);
    expect(code(bad)).toBe('invalid_request');
  });

  it('GET /v1/exercises/{id}/history returns sets, best set and e1RM over time', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('hist');
    await seedUser(uid);
    await stamped(deps, uid, 'old', new Date('2026-11-16T18:00:00Z'), {
      exercises: [{ exerciseId: 'bench-press', name: 'Bench press', sets: [{ n: 1, weight: 75, reps: 5, type: 'working', done: true }] }],
    });
    await stamped(deps, uid, 'new', new Date('2026-11-17T18:00:00Z'));
    await stamped(deps, uid, 'other', new Date('2026-11-18T08:00:00Z'), {
      exercises: [{ exerciseId: 'squat', name: 'Squat', sets: [{ n: 1, weight: 100, reps: 5, type: 'working', done: true }] }],
    });
    const tok = await token(deps, uid, ['read:sessions']);
    const res = await get(deps, '/v1/exercises/bench-press/history', tok);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      exerciseId: 'bench-press',
      name: 'Bench press',
      // 80 x 5 gives an Epley e1RM of 93.3; 82.5 x 3 gives 90.8.
      bestSet: { weightKg: 80, reps: 5 },
      bestE1rmKg: 93.3,
      lastPerformedAt: '2026-11-17T18:00:00.000Z',
      history: [
        {
          sessionId: 'new',
          startedAt: '2026-11-17T18:00:00.000Z',
          e1rmKg: 93.3,
          sets: [
            { type: 'warmup', weightKg: 40, reps: 10 },
            { type: 'working', weightKg: 80, reps: 5 },
            { type: 'working', weightKg: 82.5, reps: 3 },
          ],
        },
        { sessionId: 'old', startedAt: '2026-11-16T18:00:00.000Z', e1rmKg: 87.5, sets: [{ type: 'working', weightKg: 75, reps: 5 }] },
      ],
      nextCursor: null,
    });
    expect((await get(deps, '/v1/exercises/deadlift/history', tok)).status).toBe(404);
  });

  it('is read-only: POST gives 405, an unknown path 404', async () => {
    const deps = testDeps({ now: () => NOW });
    const post = await handleApi(deps, { method: 'POST', path: '/v1/sessions', query: {}, headers: {} });
    expect(post.status).toBe(405);
    expect(code(post)).toBe('method_not_allowed');
    expect(post.headers.Allow).toBe('GET');
    const unknown = await get(deps, '/v1/routines');
    expect(unknown.status).toBe(404);
    expect(code(unknown)).toBe('not_found');
  });

  it('logs one line per request and never the token', async () => {
    const lines: Array<{ message: string; data?: Record<string, unknown> }> = [];
    const log = { info: (message: string, data?: Record<string, unknown>) => lines.push({ message, data }), warn: () => undefined };
    const deps = testDeps({ now: () => NOW, log });
    const uid = newUid('log');
    await seedUser(uid);
    const tok = await token(deps, uid, ['read:profile']);
    lines.length = 0;
    await get(deps, '/v1/me', tok);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ message: 'api', data: { route: 'getMe', status: 200, uid } });
    expect(JSON.stringify(lines)).not.toContain(tok);
  });
});

describe('agent API: OpenAPI document', () => {
  it('is served at /v1/openapi.json without a token, validates as OpenAPI 3.1 and lists all five paths', async () => {
    const res = await get(testDeps(), '/v1/openapi.json');
    expect(res.status).toBe(200);
    const doc = res.body as { openapi: string; paths: Record<string, Record<string, { security: unknown[] }>> };
    expect(doc.openapi).toBe('3.1.0');

    const { Validator } = await import('@seriousme/openapi-schema-validator');
    const validator = new Validator();
    const result = await validator.validate(JSON.parse(JSON.stringify(doc)));
    expect(result.errors ?? []).toEqual([]);
    expect(result.valid).toBe(true);
    expect(validator.version).toBe('3.1');

    for (const p of [
      '/v1/me',
      '/v1/stats',
      '/v1/sessions',
      '/v1/sessions/{id}',
      '/v1/exercises/{id}/history',
    ]) {
      expect(doc.paths[p], p).toBeDefined();
      expect(doc.paths[p].get.security).toHaveLength(1);
    }
  });
});
