import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc, Timestamp } from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { newUid, PROJECT_ID, requireEmulator } from './helpers';

let env: RulesTestEnvironment;
let alice: string;
let bob: string;

beforeAll(async () => {
  requireEmulator();
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST!.split(':');
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8'), host, port: Number(port) },
  });
});

afterAll(async () => {
  await env?.cleanup();
});

/** Seed Bob's and Alice's documents with rules off, as the functions would. */
beforeEach(async () => {
  alice = newUid('alice');
  bob = newUid('bob');
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [alice, bob]) {
      await setDoc(doc(db, `users/${uid}`), { displayName: uid, goalPerWeek: 3, timezone: 'UTC', streakWeeks: 2, proofCount: 5 });
      await setDoc(doc(db, `users/${uid}/sessions/draft1`), { status: 'draft', startedAt: Timestamp.now() });
      await setDoc(doc(db, `users/${uid}/sessions/stamped1`), { status: 'stamped', proofNumber: 5, startedAt: Timestamp.now() });
      await setDoc(doc(db, `users/${uid}/routines/r1`), { name: 'Push A', order: 0, exercises: [] });
      await setDoc(doc(db, `users/${uid}/exerciseStats/bench`), { bestWeight: 80, sessionCount: 3 });
      await setDoc(doc(db, `users/${uid}/agentTokens/t1`), { name: 'my agent', prefix: 'pgym_pat', tokenHash: 'x' });
    }
  });
});

const as = (uid: string) => env.authenticatedContext(uid).firestore();

describe('user A cannot read or write user B', () => {
  it('reads of every collection of another user are denied', async () => {
    const db = as(alice);
    await assertFails(getDoc(doc(db, `users/${bob}`)));
    await assertFails(getDoc(doc(db, `users/${bob}/sessions/draft1`)));
    await assertFails(getDoc(doc(db, `users/${bob}/routines/r1`)));
    await assertFails(getDoc(doc(db, `users/${bob}/exerciseStats/bench`)));
    await assertFails(getDoc(doc(db, `users/${bob}/agentTokens/t1`)));
  });

  it('writes to another user are denied', async () => {
    const db = as(alice);
    await assertFails(updateDoc(doc(db, `users/${bob}`), { displayName: 'mine now' }));
    await assertFails(setDoc(doc(db, `users/${bob}/sessions/new1`), { status: 'draft' }));
    await assertFails(updateDoc(doc(db, `users/${bob}/sessions/draft1`), { routineName: 'x' }));
    await assertFails(setDoc(doc(db, `users/${bob}/routines/r2`), { name: 'x' }));
    await assertFails(deleteDoc(doc(db, `users/${bob}/routines/r1`)));
  });

  it('signed-out callers can read nothing', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, `users/${alice}`)));
    await assertFails(getDoc(doc(db, `users/${alice}/sessions/draft1`)));
  });

  it('the owner can read and write their own documents', async () => {
    const db = as(alice);
    await assertSucceeds(getDoc(doc(db, `users/${alice}`)));
    await assertSucceeds(getDoc(doc(db, `users/${alice}/sessions/stamped1`)));
    await assertSucceeds(getDoc(doc(db, `users/${alice}/exerciseStats/bench`)));
    await assertSucceeds(getDoc(doc(db, `users/${alice}/agentTokens/t1`)));
    await assertSucceeds(updateDoc(doc(db, `users/${alice}`), { goalPerWeek: 4, reminderTime: '18:00' }));
    await assertSucceeds(setDoc(doc(db, `users/${alice}/routines/r2`), { name: 'Pull A', order: 1, exercises: [] }));
    await assertSucceeds(setDoc(doc(db, `users/${alice}/sessions/new1`), { status: 'draft', startedAt: Timestamp.now() }));
    await assertSucceeds(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { status: 'finished', setCount: 3 }));
  });
});

describe('server-owned fields are denied to clients', () => {
  it('proofNumber on a new or existing session', async () => {
    const db = as(alice);
    await assertFails(setDoc(doc(db, `users/${alice}/sessions/new2`), { status: 'draft', proofNumber: 1 }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { proofNumber: 99 }));
  });

  it('stampedAt on a new or existing session', async () => {
    const db = as(alice);
    await assertFails(setDoc(doc(db, `users/${alice}/sessions/new3`), { status: 'draft', stampedAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { stampedAt: Timestamp.now() }));
  });

  it('privacy-first proof metadata on a session', async () => {
    const db = as(alice);
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { photoSHA256: 'a'.repeat(64) }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { cardFormatVersion: 1 }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { cardFilter: 'iron' }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { proofImageCreated: true }));
  });

  it('physique on a session', async () => {
    const db = as(alice);
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { physique: { score: 99, tip: 'x' } }));
    await assertFails(setDoc(doc(db, `users/${alice}/sessions/new4`), { status: 'draft', physique: { score: 99 } }));
  });

  it('streakWeeks and the other counters on the user', async () => {
    const db = as(alice);
    await assertFails(updateDoc(doc(db, `users/${alice}`), { streakWeeks: 100 }));
    await assertFails(updateDoc(doc(db, `users/${alice}`), { longestStreak: 100 }));
    await assertFails(updateDoc(doc(db, `users/${alice}`), { passWeeks: 9 }));
    await assertFails(updateDoc(doc(db, `users/${alice}`), { proofCount: 9 }));
    await assertFails(updateDoc(doc(db, `users/${alice}`), { lastProofNumber: 9 }));
    await assertFails(updateDoc(doc(db, `users/${alice}`), { 'streakState.weekCount': 9 }));
    const fresh = newUid('carol');
    await assertFails(setDoc(doc(as(fresh), `users/${fresh}`), { displayName: 'c', streakWeeks: 50 }));
    await assertSucceeds(setDoc(doc(as(fresh), `users/${fresh}`), { displayName: 'c', goalPerWeek: 3, timezone: 'UTC' }));
  });

  it('a client cannot mark a session stamped or change a stamped one', async () => {
    const db = as(alice);
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/draft1`), { status: 'stamped' }));
    await assertFails(setDoc(doc(db, `users/${alice}/sessions/new5`), { status: 'stamped' }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/stamped1`), { routineName: 'edited' }));
    await assertFails(updateDoc(doc(db, `users/${alice}/sessions/stamped1`), { status: 'draft' }));
  });

  it('exercise stats and agent tokens are read-only for clients', async () => {
    const db = as(alice);
    await assertFails(setDoc(doc(db, `users/${alice}/exerciseStats/bench`), { bestWeight: 500 }));
    await assertFails(setDoc(doc(db, `users/${alice}/agentTokens/t2`), { tokenHash: 'abc', scopes: ['read:photos'] }));
  });

  it('deletes go through functions, not the client', async () => {
    const db = as(alice);
    await assertFails(deleteDoc(doc(db, `users/${alice}`)));
    await assertFails(deleteDoc(doc(db, `users/${alice}/sessions/draft1`)));
  });

  it('a goal outside 2 to 6 is rejected', async () => {
    const db = as(alice);
    await assertFails(updateDoc(doc(db, `users/${alice}`), { goalPerWeek: 7 }));
    await assertFails(updateDoc(doc(db, `users/${alice}`), { goalPerWeek: 1 }));
  });

  it('the waitlist is closed to clients', async () => {
    await assertFails(setDoc(doc(as(alice), 'waitlist/w1'), { email: 'someone@example.com' }));
    await assertFails(getDoc(doc(as(alice), 'waitlist/w1')));
  });
});
