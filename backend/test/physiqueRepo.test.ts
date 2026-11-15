import { Timestamp } from 'firebase-admin/firestore';
import { beforeAll, describe, expect, it } from 'vitest';
import * as h from '../src/handlers';
import { analyzePhysique, type PhysiqueDeps } from '../src/physique';
import { FirestorePhysiqueRepo } from '../src/physiqueRepo';
import { cardKey, photoKey } from '../src/photoStore';
import { FakePhotoStore, adminDb, newUid, requireEmulator, silentLog, testDeps } from './helpers';
import { FakeVisionModel } from './physiqueFakes';

beforeAll(() => requireEmulator());

const NOW = new Date('2026-11-18T18:00:00Z');

async function seedUser(uid: string, fields: Record<string, unknown> = {}) {
  await adminDb().doc(`users/${uid}`).set({ timezone: 'UTC', goalPerWeek: 3, birthYear: 1990, physiqueConsent: true, ...fields });
}

async function seedStamped(uid: string, id: string, fields: Record<string, unknown> = {}) {
  await adminDb().doc(`users/${uid}/sessions/${id}`).set({ status: 'stamped', startedAt: Timestamp.fromDate(NOW), ...fields });
}

function deps(model = new FakeVisionModel()): PhysiqueDeps & { store: FakePhotoStore; model: FakeVisionModel } {
  return { repo: new FirestorePhysiqueRepo(adminDb()), store: new FakePhotoStore(), model, now: () => NOW, log: silentLog };
}

const physiqueOf = async (uid: string, id: string) => (await adminDb().doc(`users/${uid}/sessions/${id}`).get()).get('physique');

describe('analyzePhysique on Firestore', () => {
  it('writes the score on the session with a server Timestamp', async () => {
    const uid = newUid('p');
    await seedUser(uid);
    await seedStamped(uid, 's1');
    const d = deps(new FakeVisionModel().reply({ usable: true, refusedReason: null, score: 140, tip: 'Add rows.' }));
    d.store.put(photoKey(uid, 's1'));

    expect(await analyzePhysique(d, { uid, sessionId: 's1' })).toMatchObject({ status: 'scored', score: 100 });
    const p = await physiqueOf(uid, 's1');
    expect(p).toMatchObject({ score: 100, rawScore: 100, tip: 'Add rows.', model: 'fake-vision-model' });
    expect(p.analyzedAt).toBeInstanceOf(Timestamp);
    expect(p.analyzedAt.toDate()).toEqual(NOW);
    expect(p).not.toHaveProperty('refusedReason');
  });

  it('no consent: no model call, nothing written', async () => {
    const uid = newUid('p');
    await seedUser(uid, { physiqueConsent: false });
    await seedStamped(uid, 's1');
    const d = deps();
    d.store.put(photoKey(uid, 's1'));
    expect(await analyzePhysique(d, { uid, sessionId: 's1' })).toMatchObject({ reason: 'no_consent' });
    expect(d.model.calls).toHaveLength(0);
    expect(await physiqueOf(uid, 's1')).toBeUndefined();
  });

  it('malformed output writes refusedReason and no score', async () => {
    const uid = newUid('p');
    await seedUser(uid);
    await seedStamped(uid, 's1');
    const d = deps(new FakeVisionModel().reply('{oops'));
    d.store.put(photoKey(uid, 's1'));
    await analyzePhysique(d, { uid, sessionId: 's1' });
    const p = await physiqueOf(uid, 's1');
    expect(p.refusedReason).toBe('failure');
    expect(p).not.toHaveProperty('score');
  });

  it('counts the daily limit from session documents and refuses the fourth', async () => {
    const uid = newUid('p');
    await seedUser(uid);
    const d = deps();
    for (const id of ['s1', 's2', 's3', 's4']) {
      await seedStamped(uid, id);
      d.store.put(photoKey(uid, id));
    }
    // Yesterday's analyses do not count.
    await seedStamped(uid, 'old', {
      physique: { score: 40, rawScore: 40, model: 'm', analyzedAt: Timestamp.fromDate(new Date('2026-11-17T23:00:00Z')) },
    });
    for (const id of ['s1', 's2', 's3']) expect(await analyzePhysique(d, { uid, sessionId: id })).toMatchObject({ status: 'scored' });
    expect(await analyzePhysique(d, { uid, sessionId: 's4' })).toMatchObject({ status: 'refused', refusedReason: 'daily_limit' });
    expect(d.model.calls).toHaveLength(3);
    expect(await physiqueOf(uid, 's4')).toMatchObject({ refusedReason: 'daily_limit' });
  });

  it('smooths against the last raw scores read from Firestore', async () => {
    const uid = newUid('p');
    await seedUser(uid);
    const at = (iso: string) => Timestamp.fromDate(new Date(iso));
    await seedStamped(uid, 'a', { physique: { score: 50, rawScore: 50, model: 'm', analyzedAt: at('2026-11-10T10:00:00Z') } });
    await seedStamped(uid, 'b', { physique: { score: 55, rawScore: 60, model: 'm', analyzedAt: at('2026-11-12T10:00:00Z') } });
    await seedStamped(uid, 'c', { physique: { score: 70, model: 'm', analyzedAt: at('2026-11-14T10:00:00Z') } }); // no rawScore: score is used
    await seedStamped(uid, 's1');
    const d = deps(new FakeVisionModel().reply({ usable: true, refusedReason: null, score: 90, tip: null }));
    d.store.put(photoKey(uid, 's1'));
    expect(await analyzePhysique(d, { uid, sessionId: 's1' })).toMatchObject({ score: 72, rawScore: 90 });
  });

  it('claims a session once even when two tasks race', async () => {
    const uid = newUid('p');
    await seedUser(uid);
    await seedStamped(uid, 's1');
    const d = deps();
    d.store.put(photoKey(uid, 's1'));
    const outs = await Promise.all([analyzePhysique(d, { uid, sessionId: 's1' }), analyzePhysique(d, { uid, sessionId: 's1' })]);
    expect(outs.filter((o) => o.status === 'scored')).toHaveLength(1);
    expect(d.model.calls).toHaveLength(1);
  });
});

describe('stampSession queues analyzePhysique', () => {
  async function stampWith(fields: Record<string, unknown>, enqueue: (uid: string, s: string) => Promise<void>) {
    const uid = newUid('q');
    await adminDb().doc(`users/${uid}`).set({ timezone: 'UTC', goalPerWeek: 3, birthYear: 1990, ...fields });
    await adminDb().doc(`users/${uid}/sessions/s1`).set({
      status: 'finished',
      startedAt: Timestamp.fromDate(new Date(NOW.getTime() - 3_600_000)),
      timezone: 'UTC',
      exercises: [],
    });
    const d = testDeps({ now: () => NOW, enqueuePhysique: enqueue });
    d.store.put(photoKey(uid, 's1'));
    d.store.put(cardKey(uid, 's1'));
    return { uid, result: await h.stampSession(d, uid, { sessionId: 's1' }) };
  }

  it('queues only with consent and age, and a queue error does not fail the stamp', async () => {
    const queued: string[] = [];
    const record = async (uid: string) => void queued.push(uid);
    const yes = await stampWith({ physiqueConsent: true }, record);
    await stampWith({ physiqueConsent: false }, record);
    await stampWith({ physiqueConsent: true, birthYear: 2010 }, record);
    expect(queued).toEqual([yes.uid]);

    const broken = await stampWith({ physiqueConsent: true }, async () => {
      throw new Error('queue down');
    });
    expect(broken.result.proofNumber).toBe(1);
  });
});
