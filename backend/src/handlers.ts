/**
 * The logic behind each Cloud Function, with its dependencies passed in. The
 * exported functions in index.ts are thin wrappers; tests call these directly
 * against the Firestore and Auth emulators with a fake PhotoStore.
 */
import { Timestamp, type DocumentReference, type Firestore } from 'firebase-admin/firestore';
import type { Auth } from 'firebase-admin/auth';
import { HttpsError } from 'firebase-functions/v2/https';
import { isAdult } from './physique';
import {
  GET_EXPIRES_SEC,
  ID_PATTERN,
  MAX_UPLOAD_BYTES,
  PHOTO_CONTENT_TYPE,
  PUT_EXPIRES_SEC,
  cardKey,
  isOwnKey,
  photoKey,
  userPrefix,
  type PhotoStore,
} from './photoStore';
import {
  addSession,
  clampGoal,
  compareWeekKeys,
  initialState,
  isValidTimeZone,
  removeSession,
  rollTo,
  sessionWeekKey,
  view,
  weekEndsAt,
  weekKey,
  type StreakState,
} from './streak';
import {
  emptyStats,
  mergeStats,
  sanitizeExercises,
  sessionTotals,
  type ExerciseStats,
} from './sessionStats';

export interface Logger {
  info(message: string, data?: Record<string, unknown>): void;
  warn(message: string, data?: Record<string, unknown>): void;
}

export interface Deps {
  db: Firestore;
  store: PhotoStore;
  auth?: Auth;
  now: () => Date;
  log: Logger;
  /** Called after a stamp when the user has consented to the score and is 18 or over. Queues analyzePhysique. */
  enqueuePhysique?: (uid: string, sessionId: string) => Promise<void>;
}

/** rollWeek closes a week this long after local midnight on Sunday, so a late stamp still lands. */
export const ROLL_GRACE_MS = 6 * 60 * 60 * 1000;
/** A session may not claim to start later than this past the server clock. */
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;
const MAX_KEYS_PER_CALL = 60;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireUid(uid: string | undefined): string {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function requireSessionId(data: unknown): string {
  const id = (data as { sessionId?: unknown } | null)?.sessionId;
  if (typeof id !== 'string' || !ID_PATTERN.test(id)) {
    throw new HttpsError('invalid-argument', 'sessionId is missing or malformed.');
  }
  return id;
}

function sessionRef(db: Firestore, uid: string, sessionId: string): DocumentReference {
  return db.doc(`users/${uid}/sessions/${sessionId}`);
}

export function toDate(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

export function userTimeZone(user: FirebaseFirestore.DocumentData | undefined): string {
  return isValidTimeZone(user?.timezone) ? user.timezone : 'UTC';
}

interface StoredStreakState extends StreakState {
  closesAt: Timestamp;
}

export function readStreakState(raw: unknown): StreakState | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.weekKey !== 'string') return null;
  const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
  return {
    weekKey: r.weekKey,
    weekGoal: clampGoal(r.weekGoal),
    weekCount: num(r.weekCount),
    streakClosed: num(r.streakClosed),
    longestClosed: num(r.longestClosed),
    passClosed: num(r.passClosed),
    hitsTowardPass: num(r.hitsTowardPass),
  };
}

function storeStreakState(state: StreakState, timeZone: string): StoredStreakState {
  const closesAt = new Date(weekEndsAt(state.weekKey, timeZone).getTime() + ROLL_GRACE_MS);
  return { ...state, closesAt: Timestamp.fromDate(closesAt) };
}

/** The user fields derived from the streak state, ready to write. */
function streakFields(state: StreakState, timeZone: string) {
  const v = view(state);
  return {
    streakState: storeStreakState(state, timeZone),
    streakWeeks: v.streakWeeks,
    longestStreak: v.longestStreak,
    passWeeks: v.passWeeks,
  };
}

function statsFromDoc(raw: FirebaseFirestore.DocumentData | undefined): ExerciseStats {
  if (!raw) return emptyStats();
  return {
    bestWeight: typeof raw.bestWeight === 'number' ? raw.bestWeight : 0,
    bestSet: raw.bestSet ?? null,
    bestE1rm: typeof raw.bestE1rm === 'number' ? raw.bestE1rm : 0,
    lastPerformedAt: toDate(raw.lastPerformedAt),
    sessionCount: typeof raw.sessionCount === 'number' ? raw.sessionCount : 0,
  };
}

function statsToDoc(stats: ExerciseStats) {
  return {
    bestWeight: stats.bestWeight,
    bestSet: stats.bestSet,
    bestE1rm: stats.bestE1rm,
    lastPerformedAt: stats.lastPerformedAt ? Timestamp.fromDate(stats.lastPerformedAt) : null,
    sessionCount: stats.sessionCount,
  };
}

// ---------------------------------------------------------------------------
// createUploadUrls
// ---------------------------------------------------------------------------

export interface UploadUrls {
  photo: { key: string; url: string };
  card: { key: string; url: string };
  expiresInSec: number;
}

function requireBytes(data: unknown, field: 'photoBytes' | 'cardBytes'): number {
  const v = (data as Record<string, unknown> | null)?.[field];
  if (typeof v !== 'number' || !Number.isInteger(v) || v <= 0 || v > MAX_UPLOAD_BYTES) {
    throw new HttpsError('invalid-argument', `${field} must be a whole number of bytes, at most ${MAX_UPLOAD_BYTES}.`);
  }
  return v;
}

export async function createUploadUrls(deps: Deps, authUid: string | undefined, data: unknown): Promise<UploadUrls> {
  const uid = requireUid(authUid);
  const sessionId = requireSessionId(data);
  const photoBytes = requireBytes(data, 'photoBytes');
  const cardBytes = requireBytes(data, 'cardBytes');

  const snap = await sessionRef(deps.db, uid, sessionId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'No such session. Sync it before uploading.');
  if (snap.get('status') === 'stamped') throw new HttpsError('failed-precondition', 'This session is already stamped.');

  const pk = photoKey(uid, sessionId);
  const ck = cardKey(uid, sessionId);
  const [photoUrl, cardUrl] = await Promise.all([
    deps.store.presignPut(pk, PHOTO_CONTENT_TYPE, photoBytes, PUT_EXPIRES_SEC),
    deps.store.presignPut(ck, PHOTO_CONTENT_TYPE, cardBytes, PUT_EXPIRES_SEC),
  ]);
  deps.log.info('createUploadUrls', { uid, sessionId });
  return { photo: { key: pk, url: photoUrl }, card: { key: ck, url: cardUrl }, expiresInSec: PUT_EXPIRES_SEC };
}

// ---------------------------------------------------------------------------
// getPhotoUrls
// ---------------------------------------------------------------------------

export async function getPhotoUrls(
  deps: Deps,
  authUid: string | undefined,
  data: unknown,
): Promise<{ urls: Record<string, string>; expiresInSec: number }> {
  const uid = requireUid(authUid);
  const keys = (data as { keys?: unknown } | null)?.keys;
  if (!Array.isArray(keys) || keys.length === 0 || keys.length > MAX_KEYS_PER_CALL) {
    throw new HttpsError('invalid-argument', `keys must be a list of 1 to ${MAX_KEYS_PER_CALL} keys.`);
  }
  for (const key of keys) {
    if (!isOwnKey(uid, key)) throw new HttpsError('permission-denied', 'You can only read your own photos.');
  }
  const unique = [...new Set(keys as string[])];
  const signed = await Promise.all(unique.map((k) => deps.store.presignGet(k, GET_EXPIRES_SEC)));
  const urls: Record<string, string> = {};
  unique.forEach((k, i) => (urls[k] = signed[i]));
  deps.log.info('getPhotoUrls', { uid, count: unique.length });
  return { urls, expiresInSec: GET_EXPIRES_SEC };
}

// ---------------------------------------------------------------------------
// stampSession
// ---------------------------------------------------------------------------

export interface StampResult {
  sessionId: string;
  proofNumber: number;
  stampedAt: string;
  weekKey: string;
  weekCount: number;
  weekGoal: number;
  streakWeeks: number;
  longestStreak: number;
  passWeeks: number;
  proofCount: number;
  setCount: number;
  totalVolume: number;
  durationSec: number;
  newBests: string[];
  alreadyStamped: boolean;
}

function resultFromStamped(sessionId: string, s: FirebaseFirestore.DocumentData, u: FirebaseFirestore.DocumentData | undefined): StampResult {
  const state = readStreakState(u?.streakState);
  return {
    sessionId,
    proofNumber: s.proofNumber,
    stampedAt: (toDate(s.stampedAt) ?? new Date(0)).toISOString(),
    weekKey: s.weekKey,
    weekCount: state?.weekCount ?? 0,
    weekGoal: state?.weekGoal ?? clampGoal(u?.goalPerWeek),
    streakWeeks: u?.streakWeeks ?? 0,
    longestStreak: u?.longestStreak ?? 0,
    passWeeks: u?.passWeeks ?? 0,
    proofCount: u?.proofCount ?? 0,
    setCount: s.setCount ?? 0,
    totalVolume: s.totalVolume ?? 0,
    durationSec: s.durationSec ?? 0,
    newBests: s.newBests ?? [],
    alreadyStamped: true,
  };
}

export async function stampSession(deps: Deps, authUid: string | undefined, data: unknown): Promise<StampResult> {
  const uid = requireUid(authUid);
  const sessionId = requireSessionId(data);
  const sRef = sessionRef(deps.db, uid, sessionId);
  const uRef = deps.db.doc(`users/${uid}`);

  const first = await sRef.get();
  if (!first.exists) throw new HttpsError('not-found', 'No such session.');
  if (first.get('status') === 'stamped') {
    return resultFromStamped(sessionId, first.data()!, (await uRef.get()).data());
  }

  const pk = photoKey(uid, sessionId);
  const ck = cardKey(uid, sessionId);
  const [hasPhoto, hasCard] = await Promise.all([deps.store.exists(pk), deps.store.exists(ck)]);
  if (!hasPhoto) throw new HttpsError('failed-precondition', 'The photo has not been uploaded.');
  if (!hasCard) throw new HttpsError('failed-precondition', 'The card has not been uploaded.');

  const result = await deps.db.runTransaction(async (tx) => {
    const [sSnap, uSnap] = await Promise.all([tx.get(sRef), tx.get(uRef)]);
    if (!sSnap.exists) throw new HttpsError('not-found', 'No such session.');
    if (!uSnap.exists) throw new HttpsError('failed-precondition', 'Finish onboarding first.');
    const s = sSnap.data()!;
    const u = uSnap.data()!;
    if (s.status === 'stamped') return resultFromStamped(sessionId, s, u);

    const now = deps.now();
    const startedAt = toDate(s.startedAt);
    if (!startedAt) throw new HttpsError('invalid-argument', 'The session has no start time.');
    if (startedAt.getTime() > now.getTime() + MAX_CLOCK_SKEW_MS) {
      throw new HttpsError('invalid-argument', 'The session starts in the future.');
    }
    const claimedEnd = toDate(s.endedAt);
    const endedAt =
      claimedEnd && claimedEnd >= startedAt && claimedEnd.getTime() <= now.getTime() + MAX_CLOCK_SKEW_MS
        ? claimedEnd
        : now;
    const durationSec = Math.round((endedAt.getTime() - startedAt.getTime()) / 1000);

    const userTz = userTimeZone(u);
    const sessionTz = isValidTimeZone(s.timezone) ? s.timezone : userTz;
    const sWeek = sessionWeekKey(startedAt, sessionTz);
    const goal = clampGoal(u.goalPerWeek);

    // Streak.
    const prior = readStreakState(u.streakState) ?? initialState(weekKey(now, userTz), goal);
    const placed = addSession(prior, sWeek, goal);
    const streak = streakFields(placed.state, userTz);

    // Totals and exercise stats. Every read must come before any write.
    const exercises = sanitizeExercises(s.exercises);
    const totals = sessionTotals(exercises);
    const ids = [...totals.perExercise.keys()];
    const statRefs = ids.map((id) => deps.db.doc(`users/${uid}/exerciseStats/${id}`));
    const statSnaps = statRefs.length > 0 ? await tx.getAll(...statRefs) : [];

    const proofNumber = (typeof u.lastProofNumber === 'number' ? u.lastProofNumber : 0) + 1;
    const proofCount = (typeof u.proofCount === 'number' ? u.proofCount : 0) + 1;
    const stampedAt = Timestamp.fromDate(now);

    const newBests: string[] = [];
    statSnaps.forEach((snap, i) => {
      const merged = mergeStats(statsFromDoc(snap.data()), totals.perExercise.get(ids[i])!, startedAt);
      if (merged.isNewBest) newBests.push(ids[i]);
      tx.set(statRefs[i], statsToDoc(merged.stats));
    });

    tx.update(sRef, {
      status: 'stamped',
      proofNumber,
      stampedAt,
      weekKey: sWeek,
      timezone: sessionTz,
      endedAt: Timestamp.fromDate(endedAt),
      durationSec,
      setCount: totals.setCount,
      totalVolume: totals.totalVolume,
      newBests,
      photoKey: pk,
      cardKey: ck,
    });
    tx.update(uRef, { ...streak, lastProofNumber: proofNumber, proofCount });

    const v = view(placed.state);
    const out: StampResult = {
      sessionId,
      proofNumber,
      stampedAt: now.toISOString(),
      weekKey: sWeek,
      weekCount: placed.state.weekCount,
      weekGoal: placed.state.weekGoal,
      streakWeeks: v.streakWeeks,
      longestStreak: v.longestStreak,
      passWeeks: v.passWeeks,
      proofCount,
      setCount: totals.setCount,
      totalVolume: totals.totalVolume,
      durationSec,
      newBests,
      alreadyStamped: false,
    };
    if (placed.placement === 'late') {
      deps.log.warn('stampSession late session, streak unchanged', { uid, sessionId, sessionWeek: sWeek, openWeek: prior.weekKey });
    }
    return out;
  });

  deps.log.info('stampSession', {
    uid,
    sessionId,
    proofNumber: result.proofNumber,
    weekKey: result.weekKey,
    alreadyStamped: result.alreadyStamped,
  });

  if (!result.alreadyStamped && deps.enqueuePhysique) {
    const u = (await uRef.get()).data();
    if (u?.physiqueConsent === true && isAdult(u.birthYear, deps.now())) {
      // The stamp is already committed; a queue error must not fail it. The session simply has no score.
      try {
        await deps.enqueuePhysique(uid, sessionId);
      } catch (err) {
        deps.log.warn('stampSession could not queue analyzePhysique', { uid, sessionId, error: String(err) });
      }
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// deleteSession
// ---------------------------------------------------------------------------

export async function deleteSession(
  deps: Deps,
  authUid: string | undefined,
  data: unknown,
): Promise<{ sessionId: string; deleted: boolean }> {
  const uid = requireUid(authUid);
  const sessionId = requireSessionId(data);
  const sRef = sessionRef(deps.db, uid, sessionId);
  const uRef = deps.db.doc(`users/${uid}`);

  // Objects first: if this fails the document is still there and the call can be retried.
  await deps.store.deleteKeys([photoKey(uid, sessionId), cardKey(uid, sessionId)]);

  const deleted = await deps.db.runTransaction(async (tx) => {
    const [sSnap, uSnap] = await Promise.all([tx.get(sRef), tx.get(uRef)]);
    if (!sSnap.exists) return false;
    const s = sSnap.data()!;
    const u = uSnap.data();
    const wasStamped = s.status === 'stamped';

    let statWrites: Array<{ ref: DocumentReference; stats: ExerciseStats | null }> = [];
    if (wasStamped) {
      // Rebuild the stats of this session's exercises from the stamped sessions that remain.
      const ids = [...sessionTotals(sanitizeExercises(s.exercises)).perExercise.keys()];
      if (ids.length > 0) {
        const remaining = await tx.get(deps.db.collection(`users/${uid}/sessions`).where('status', '==', 'stamped'));
        const rebuilt = new Map<string, ExerciseStats>(ids.map((id) => [id, emptyStats()]));
        const others = remaining.docs
          .filter((d) => d.id !== sessionId)
          .map((d) => ({ startedAt: toDate(d.get('startedAt')) ?? new Date(0), totals: sessionTotals(sanitizeExercises(d.get('exercises'))) }))
          .sort((a, b) => a.startedAt.getTime() - b.startedAt.getTime());
        for (const o of others) {
          for (const id of ids) {
            const per = o.totals.perExercise.get(id);
            if (per) rebuilt.set(id, mergeStats(rebuilt.get(id)!, per, o.startedAt).stats);
          }
        }
        statWrites = ids.map((id) => {
          const st = rebuilt.get(id)!;
          return { ref: deps.db.doc(`users/${uid}/exerciseStats/${id}`), stats: st.sessionCount > 0 ? st : null };
        });
      }
    }

    tx.delete(sRef);
    for (const w of statWrites) {
      if (w.stats) tx.set(w.ref, statsToDoc(w.stats));
      else tx.delete(w.ref);
    }
    if (wasStamped && u) {
      const tz = userTimeZone(u);
      const state = readStreakState(u.streakState);
      const update: Record<string, unknown> = {
        proofCount: Math.max(0, (typeof u.proofCount === 'number' ? u.proofCount : 1) - 1),
      };
      if (state && typeof s.weekKey === 'string') Object.assign(update, streakFields(removeSession(state, s.weekKey), tz));
      tx.update(uRef, update);
    }
    return true;
  });

  deps.log.info('deleteSession', { uid, sessionId, deleted });
  return { sessionId, deleted };
}

// ---------------------------------------------------------------------------
// deleteAccount
// ---------------------------------------------------------------------------

export async function deleteAccount(
  deps: Deps,
  authUid: string | undefined,
): Promise<{ deletedObjects: number }> {
  const uid = requireUid(authUid);

  // 1. Every S3 object under the user.
  const keys = await deps.store.listKeys(userPrefix(uid));
  if (keys.length > 0) await deps.store.deleteKeys(keys);

  // 2. Every document: the user and all subcollections.
  await deps.db.recursiveDelete(deps.db.doc(`users/${uid}`));

  // 3. The auth user last, so a failure above can be retried while still signed in.
  if (deps.auth) {
    try {
      await deps.auth.deleteUser(uid);
    } catch (err) {
      if ((err as { code?: string }).code !== 'auth/user-not-found') throw err;
    }
  }
  // Revoking the Sign in with Apple token needs Apple's REST API and keys; not in this card.
  deps.log.info('deleteAccount', { uid, deletedObjects: keys.length });
  return { deletedObjects: keys.length };
}

// ---------------------------------------------------------------------------
// rollWeek
// ---------------------------------------------------------------------------

const ROLL_PAGE = 200;

export async function rollWeek(deps: Deps): Promise<{ usersRolled: number }> {
  const now = deps.now();
  const cutoff = Timestamp.fromDate(now);
  let usersRolled = 0;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;

  for (;;) {
    let q = deps.db
      .collection('users')
      .where('streakState.closesAt', '<=', cutoff)
      .orderBy('streakState.closesAt')
      .limit(ROLL_PAGE);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.empty) break;
    last = page.docs[page.docs.length - 1];

    for (const doc of page.docs) {
      try {
        const rolled = await deps.db.runTransaction(async (tx) => {
          const snap = await tx.get(doc.ref);
          const u = snap.data();
          const state = readStreakState(u?.streakState);
          if (!u || !state) return false;
          const tz = userTimeZone(u);
          const current = weekKey(now, tz);
          const next = compareWeekKeys(state.weekKey, current) < 0 ? rollTo(state, current, clampGoal(u.goalPerWeek)).state : state;
          // Rewrite even when the week did not change, so closesAt follows a timezone change.
          tx.update(doc.ref, streakFields(next, tz));
          return next !== state;
        });
        if (rolled) usersRolled += 1;
      } catch (err) {
        deps.log.warn('rollWeek user failed', { uid: doc.id, error: String(err) });
      }
    }
    if (page.size < ROLL_PAGE) break;
  }

  deps.log.info('rollWeek', { usersRolled, at: now.toISOString() });
  return { usersRolled };
}
