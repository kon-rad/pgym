import { Timestamp } from 'firebase-admin/firestore';
import { beforeAll, describe, expect, it } from 'vitest';
import * as h from '../src/handlers';
import { cardKey, photoKey } from '../src/photoStore';
import { adminAuth, adminDb, newUid, requireEmulator, testDeps } from './helpers';

beforeAll(() => requireEmulator());

const NOW = new Date('2026-11-18T18:00:00Z'); // Wednesday of 2026-W47

async function seedUser(uid: string, fields: Record<string, unknown> = {}): Promise<void> {
  await adminDb().doc(`users/${uid}`).set({
    displayName: uid,
    timezone: 'UTC',
    goalPerWeek: 3,
    birthYear: 1990,
    createdAt: Timestamp.fromDate(new Date('2026-11-01T00:00:00Z')),
    ...fields,
  });
}

async function seedSession(uid: string, id: string, fields: Record<string, unknown> = {}): Promise<void> {
  await adminDb().doc(`users/${uid}/sessions/${id}`).set({
    status: 'finished',
    routineName: 'Push A',
    startedAt: Timestamp.fromDate(new Date(NOW.getTime() - 60 * 60 * 1000)),
    endedAt: Timestamp.fromDate(new Date(NOW.getTime() - 5 * 60 * 1000)),
    timezone: 'UTC',
    exercises: [
      {
        exerciseId: 'bench',
        name: 'Bench press',
        sets: [
          { n: 1, weight: 40, reps: 10, type: 'warmup', done: true },
          { n: 2, weight: 80, reps: 5, type: 'working', done: true },
          { n: 3, weight: 82.5, reps: 3, type: 'working', done: true },
          { n: 4, weight: 85, reps: 1, type: 'working', done: false },
        ],
      },
    ],
    ...fields,
  });
}

function uploadBoth(store: { put(k: string): void }, uid: string, sessionId: string): void {
  store.put(photoKey(uid, sessionId));
  store.put(cardKey(uid, sessionId));
}

async function expectHttpsError(p: Promise<unknown>, code: string): Promise<void> {
  await expect(p).rejects.toMatchObject({ code });
}

describe('stampSession', () => {
  it('fails when the photo object is missing, and changes nothing', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid);
    await seedSession(uid, 's1');
    deps.store.put(cardKey(uid, 's1')); // card uploaded, photo not

    await expectHttpsError(h.stampSession(deps, uid, { sessionId: 's1' }), 'failed-precondition');

    const s = (await adminDb().doc(`users/${uid}/sessions/s1`).get()).data()!;
    expect(s.status).toBe('finished');
    expect(s.proofNumber).toBeUndefined();
    expect(s.stampedAt).toBeUndefined();
    const u = (await adminDb().doc(`users/${uid}`).get()).data()!;
    expect(u.proofCount).toBeUndefined();
  });

  it('stamps with the server clock, proof number 1 and server-computed totals', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid);
    await seedSession(uid, 's1', { stampedAt: Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')), setCount: 999 });
    uploadBoth(deps.store, uid, 's1');

    const r = await h.stampSession(deps, uid, { sessionId: 's1' });

    expect(r).toMatchObject({
      proofNumber: 1,
      stampedAt: NOW.toISOString(),
      weekKey: '2026-W47',
      weekCount: 1,
      weekGoal: 3,
      proofCount: 1,
      setCount: 2, // warm-up and undone sets do not count
      totalVolume: 80 * 5 + 82.5 * 3,
      alreadyStamped: false,
    });
    const s = (await adminDb().doc(`users/${uid}/sessions/s1`).get()).data()!;
    expect(s.status).toBe('stamped');
    expect(s.stampedAt.toDate().toISOString()).toBe(NOW.toISOString());
    expect(s.photoKey).toBe(photoKey(uid, 's1'));
    const stats = (await adminDb().doc(`users/${uid}/exerciseStats/bench`).get()).data()!;
    expect(stats).toMatchObject({ bestWeight: 82.5, sessionCount: 1 });
    const u = (await adminDb().doc(`users/${uid}`).get()).data()!;
    expect(u).toMatchObject({ proofCount: 1, lastProofNumber: 1, streakWeeks: 0 });
    expect(u.streakState).toMatchObject({ weekKey: '2026-W47', weekCount: 1, weekGoal: 3 });
  });

  it('two concurrent calls for two sessions get two different consecutive proof numbers', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid, { lastProofNumber: 41, proofCount: 41 });
    await seedSession(uid, 'a');
    await seedSession(uid, 'b');
    uploadBoth(deps.store, uid, 'a');
    uploadBoth(deps.store, uid, 'b');

    const [ra, rb] = await Promise.all([
      h.stampSession(deps, uid, { sessionId: 'a' }),
      h.stampSession(deps, uid, { sessionId: 'b' }),
    ]);

    expect([ra.proofNumber, rb.proofNumber].sort((x, y) => x - y)).toEqual([42, 43]);
    const u = (await adminDb().doc(`users/${uid}`).get()).data()!;
    expect(u.lastProofNumber).toBe(43);
    expect(u.proofCount).toBe(43);
    expect(u.streakState.weekCount).toBe(2);
  });

  it('two concurrent calls for the same session stamp it once', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid);
    await seedSession(uid, 's1');
    uploadBoth(deps.store, uid, 's1');

    const [r1, r2] = await Promise.all([
      h.stampSession(deps, uid, { sessionId: 's1' }),
      h.stampSession(deps, uid, { sessionId: 's1' }),
    ]);

    expect(r1.proofNumber).toBe(1);
    expect(r2.proofNumber).toBe(1);
    expect([r1.alreadyStamped, r2.alreadyStamped].sort()).toEqual([false, true]);
    const u = (await adminDb().doc(`users/${uid}`).get()).data()!;
    expect(u.proofCount).toBe(1);
  });

  it('a session started before local midnight and stamped after counts for its start week', async () => {
    // Monday 00:20 in Los Angeles; the session started Sunday 23:50, in 2026-W47.
    const stampTime = new Date('2026-11-23T08:20:00Z');
    const deps = testDeps({ now: () => stampTime });
    const uid = newUid('u');
    await seedUser(uid, {
      timezone: 'America/Los_Angeles',
      goalPerWeek: 2,
      streakState: {
        weekKey: '2026-W47', weekGoal: 2, weekCount: 1,
        streakClosed: 0, longestClosed: 0, passClosed: 0, hitsTowardPass: 0,
        closesAt: Timestamp.fromDate(new Date('2026-11-23T14:00:00Z')),
      },
    });
    await seedSession(uid, 'late', {
      timezone: 'America/Los_Angeles',
      startedAt: Timestamp.fromDate(new Date('2026-11-23T07:50:00Z')),
      endedAt: Timestamp.fromDate(new Date('2026-11-23T08:15:00Z')),
    });
    uploadBoth(deps.store, uid, 'late');

    const r = await h.stampSession(deps, uid, { sessionId: 'late' });

    expect(r).toMatchObject({ weekKey: '2026-W47', weekCount: 2, streakWeeks: 1 });
  });

  it('rejects a caller who is not signed in and a session that does not exist', async () => {
    const deps = testDeps({ now: () => NOW });
    await expectHttpsError(h.stampSession(deps, undefined, { sessionId: 's1' }), 'unauthenticated');
    await expectHttpsError(h.stampSession(deps, newUid('u'), { sessionId: 'nope' }), 'not-found');
    await expectHttpsError(h.stampSession(deps, newUid('u'), { sessionId: '../x' }), 'invalid-argument');
  });
});

describe('createUploadUrls and getPhotoUrls', () => {
  it('signs two PUTs for the caller\'s own keys, 5 minutes, JPEG, exact size', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid);
    await seedSession(uid, 's1');

    const r = await h.createUploadUrls(deps, uid, { sessionId: 's1', photoBytes: 1_500_000, cardBytes: 400_000 });

    expect(r.photo.key).toBe(`users/${uid}/sessions/s1/photo.jpg`);
    expect(r.card.key).toBe(`users/${uid}/sessions/s1/card.jpg`);
    expect(deps.store.signedPuts).toEqual([
      { key: r.photo.key, contentType: 'image/jpeg', contentLength: 1_500_000, expiresInSec: 300 },
      { key: r.card.key, contentType: 'image/jpeg', contentLength: 400_000, expiresInSec: 300 },
    ]);
  });

  it('refuses a stamped session, an oversized file and another user\'s session', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid);
    await seedSession(uid, 'done', { status: 'stamped', proofNumber: 1 });
    await seedSession(uid, 's1');

    await expectHttpsError(h.createUploadUrls(deps, uid, { sessionId: 'done', photoBytes: 10, cardBytes: 10 }), 'failed-precondition');
    await expectHttpsError(h.createUploadUrls(deps, uid, { sessionId: 's1', photoBytes: 50_000_000, cardBytes: 10 }), 'invalid-argument');
    await expectHttpsError(h.createUploadUrls(deps, newUid('other'), { sessionId: 's1', photoBytes: 10, cardBytes: 10 }), 'not-found');
  });

  it('getPhotoUrls signs only the caller\'s own keys', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    const r = await h.getPhotoUrls(deps, uid, { keys: [photoKey(uid, 's1'), cardKey(uid, 's1')] });
    expect(Object.keys(r.urls)).toHaveLength(2);
    expect(r.expiresInSec).toBe(3600);
    await expectHttpsError(h.getPhotoUrls(deps, uid, { keys: [photoKey('someone-else', 's1')] }), 'permission-denied');
  });
});

describe('deleteSession', () => {
  it('deletes the document and both objects, and recomputes counts and stats', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    await seedUser(uid, { goalPerWeek: 2 });
    await seedSession(uid, 'a');
    await seedSession(uid, 'b', {
      exercises: [{ exerciseId: 'bench', sets: [{ weight: 100, reps: 2, type: 'working', done: true }] }],
    });
    uploadBoth(deps.store, uid, 'a');
    uploadBoth(deps.store, uid, 'b');
    await h.stampSession(deps, uid, { sessionId: 'a' });
    await h.stampSession(deps, uid, { sessionId: 'b' });
    let u = (await adminDb().doc(`users/${uid}`).get()).data()!;
    expect(u).toMatchObject({ proofCount: 2, streakWeeks: 1 });

    const r = await h.deleteSession(deps, uid, { sessionId: 'b' });

    expect(r.deleted).toBe(true);
    expect(deps.store.deleted.sort()).toEqual([cardKey(uid, 'b'), photoKey(uid, 'b')].sort());
    expect((await adminDb().doc(`users/${uid}/sessions/b`).get()).exists).toBe(false);
    u = (await adminDb().doc(`users/${uid}`).get()).data()!;
    expect(u).toMatchObject({ proofCount: 1, lastProofNumber: 2, streakWeeks: 0 });
    expect(u.streakState.weekCount).toBe(1);
    const stats = (await adminDb().doc(`users/${uid}/exerciseStats/bench`).get()).data()!;
    expect(stats).toMatchObject({ bestWeight: 82.5, sessionCount: 1 });

    // A new stamp after the delete does not reuse proof number 2.
    await seedSession(uid, 'c');
    uploadBoth(deps.store, uid, 'c');
    expect((await h.stampSession(deps, uid, { sessionId: 'c' })).proofNumber).toBe(3);
  });
});

describe('deleteAccount', () => {
  it('removes every document and calls delete for every S3 key under the user', async () => {
    const deps = testDeps({ now: () => NOW });
    const uid = newUid('u');
    const other = newUid('other');
    await adminAuth().createUser({ uid });
    await seedUser(uid);
    await seedUser(other);
    await seedSession(uid, 's1');
    await seedSession(uid, 's2');
    await seedSession(other, 's1');
    const db = adminDb();
    await db.doc(`users/${uid}/routines/r1`).set({ name: 'Push A' });
    await db.doc(`users/${uid}/exerciseStats/bench`).set({ bestWeight: 80 });
    await db.doc(`users/${uid}/agentTokens/t1`).set({ tokenHash: 'h', prefix: 'pgym_pat' });
    await db.doc(`users/${uid}/customExercises/x1`).set({ name: 'Landmine press' });
    const ownKeys = [photoKey(uid, 's1'), cardKey(uid, 's1'), photoKey(uid, 's2'), cardKey(uid, 's2'), `users/${uid}/stray.jpg`];
    ownKeys.forEach((k) => deps.store.put(k));
    deps.store.put(photoKey(other, 's1'));

    const r = await h.deleteAccount(deps, uid);

    expect(r.deletedObjects).toBe(5);
    expect([...deps.store.deleted].sort()).toEqual([...ownKeys].sort());
    expect(deps.store.objects.has(photoKey(other, 's1'))).toBe(true);
    expect((await db.doc(`users/${uid}`).get()).exists).toBe(false);
    expect(await db.doc(`users/${uid}`).listCollections()).toEqual([]);
    expect((await db.doc(`users/${other}`).get()).exists).toBe(true);
    expect((await db.doc(`users/${other}/sessions/s1`).get()).exists).toBe(true);
    await expect(adminAuth().getUser(uid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
  });
});

describe('rollWeek', () => {
  it('rolls users whose local week has ended, spending a pass when needed', async () => {
    const now = new Date('2026-11-30T12:00:00Z'); // Monday of W49
    const deps = testDeps({ now: () => now });
    const due = newUid('due');
    const notDue = newUid('notdue');
    const base = { streakClosed: 4, longestClosed: 4, passClosed: 1, hitsTowardPass: 0, weekGoal: 3 };
    await seedUser(due, {
      streakState: { ...base, weekKey: '2026-W47', weekCount: 3, closesAt: Timestamp.fromDate(new Date('2026-11-23T06:00:00Z')) },
    });
    await seedUser(notDue, {
      timezone: 'Pacific/Kiritimati',
      streakState: { ...base, weekKey: '2026-W49', weekCount: 0, closesAt: Timestamp.fromDate(new Date('2026-12-06T16:00:00Z')) },
    });

    await h.rollWeek(deps);

    const u = (await adminDb().doc(`users/${due}`).get()).data()!;
    // W47 hit (streak 5), W48 empty spends the pass (streak stays 5), W49 is open.
    expect(u).toMatchObject({ streakWeeks: 5, longestStreak: 5, passWeeks: 0 });
    expect(u.streakState).toMatchObject({ weekKey: '2026-W49', weekCount: 0, passClosed: 0 });
    expect(u.streakState.closesAt.toDate().toISOString()).toBe('2026-12-07T06:00:00.000Z');
    const n = (await adminDb().doc(`users/${notDue}`).get()).data()!;
    expect(n.streakState.weekKey).toBe('2026-W49');
    expect(n.streakState.passClosed).toBe(1);
  });
});
