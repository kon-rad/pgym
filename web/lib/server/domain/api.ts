/**
 * The agent API: the `/v1` endpoints behind the HTTP function `api`.
 *
 * `handleApi` takes a plain request and returns a plain response, so tests
 * drive it directly against the Firestore emulator. Every request:
 *   1. matches a route (404 / 405 otherwise),
 *   2. finds the token by its SHA-256 hash (401 when missing, malformed,
 *      unknown, revoked or expired),
 *   3. counts against the token's 60-a-minute window and updates lastUsedAt
 *      in one transaction (429 past the limit),
 *   4. checks the route's scope (403),
 *   5. validates path and query with the zod schemas (400),
 *   6. reads only users/{uid}/... of the token's owner and shapes the answer
 *      through the response schema, which drops any field it does not name.
 * One log line per request: route, status, token ID, uid, time. Never the token.
 */
import { AggregateField, FieldPath, Timestamp, type Firestore, type Query } from 'firebase-admin/firestore';
import type { z } from 'zod';
import { hashToken, TOKEN_PATTERN } from './agentTokens';
import {
  buildOpenApi,
  PAGE_SIZE,
  RATE_LIMIT_PER_MINUTE,
  ROUTES,
  WEEKDAYS,
  type ErrorCode,
  type Route,
  type RouteId,
  type Scope,
} from './apiSchemas';
import { readStreakState, toDate, userTimeZone, type Deps } from './handlers';
import { sanitizeExercises, sessionTotals, type LoggedSet } from './sessionStats';
import { clampGoal, dayBounds, weekKey } from './streak';

export interface ApiRequest {
  method: string;
  path: string;
  query: Record<string, unknown>;
  headers: Record<string, string | string[] | undefined>;
}

export interface ApiResponse {
  status: number;
  headers: Record<string, string>;
  body: unknown;
}

const WINDOW_MS = 60_000;
/** History scans at most this many sessions per request, then returns a cursor. */
const HISTORY_SCAN_LIMIT = 1000;
const HISTORY_BATCH = 100;
const LISTED_STATUSES = ['finished', 'stamped'];

class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
    readonly extra: Record<string, unknown> = {},
    readonly headers: Record<string, string> = {},
  ) {
    super(message);
  }
}

const badToken = (message: string) =>
  new ApiError(401, 'invalid_token', message, {}, { 'WWW-Authenticate': 'Bearer realm="pgym", error="invalid_token"' });

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

interface Matched {
  route: Route & { operationId: RouteId };
  params: Record<string, string>;
}

function compile(path: string): RegExp {
  return new RegExp(`^${path.replace(/\{(\w+)\}/g, '(?<$1>[^/]+)')}$`);
}

const COMPILED = (ROUTES as readonly (Route & { operationId: RouteId })[]).map((route) => ({ route, re: compile(route.path) }));

function normalizePath(path: string): string {
  let p = path.split('?')[0] || '/';
  if (p.startsWith('/api/v1/')) p = p.slice(4); // tolerate the function name in front
  if (p.length > 1 && p.endsWith('/')) p = p.slice(0, -1);
  return p;
}

function match(path: string): Matched | null {
  for (const { route, re } of COMPILED) {
    const m = re.exec(path);
    if (m) {
      const params: Record<string, string> = {};
      for (const [k, v] of Object.entries(m.groups ?? {})) {
        try {
          params[k] = decodeURIComponent(v);
        } catch {
          params[k] = v;
        }
      }
      return { route, params };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tokens and the rate limit
// ---------------------------------------------------------------------------

interface Caller {
  uid: string;
  tokenId: string;
  scopes: Set<Scope>;
  remaining: number;
}

function bearer(headers: ApiRequest['headers']): string {
  const raw = headers.authorization ?? headers.Authorization;
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value) throw badToken('Send the token as `Authorization: Bearer pgym_pat_...`.');
  const m = /^Bearer[ ]+(\S+)\s*$/i.exec(value);
  if (!m || !TOKEN_PATTERN.test(m[1])) throw badToken('The token is malformed.');
  return m[1];
}

async function authenticate(deps: Deps, headers: ApiRequest['headers']): Promise<Caller> {
  const token = bearer(headers);
  const found = await deps.db.collectionGroup('agentTokens').where('tokenHash', '==', hashToken(token)).limit(1).get();
  if (found.empty) throw badToken('The token is not valid.');
  const ref = found.docs[0].ref;
  const uid = ref.parent.parent?.id;
  if (!uid || ref.parent.parent?.parent.id !== 'users') throw badToken('The token is not valid.');

  return deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const t = snap.data();
    if (!t) throw badToken('The token is not valid.');
    const now = deps.now().getTime();
    if (t.revokedAt) throw badToken('The token was revoked.');
    const exp = toDate(t.expiresAt);
    if (exp && exp.getTime() <= now) throw badToken('The token has expired.');

    const windowStart = toDate(t.rateWindowStart)?.getTime() ?? 0;
    const inWindow = now - windowStart < WINDOW_MS && now >= windowStart;
    const used = inWindow && typeof t.rateCount === 'number' ? t.rateCount : 0;
    if (used >= RATE_LIMIT_PER_MINUTE) {
      const retryAfter = Math.max(1, Math.ceil((windowStart + WINDOW_MS - now) / 1000));
      throw new ApiError(429, 'rate_limited', `More than ${RATE_LIMIT_PER_MINUTE} requests in a minute. Wait ${retryAfter} s.`, {}, {
        'Retry-After': String(retryAfter),
        'X-RateLimit-Limit': String(RATE_LIMIT_PER_MINUTE),
        'X-RateLimit-Remaining': '0',
      });
    }
    tx.update(ref, {
      lastUsedAt: Timestamp.fromMillis(now),
      rateWindowStart: inWindow ? t.rateWindowStart : Timestamp.fromMillis(now),
      rateCount: used + 1,
    });
    const scopes = new Set<Scope>(Array.isArray(t.scopes) ? t.scopes : []);
    return { uid, tokenId: ref.id, scopes, remaining: RATE_LIMIT_PER_MINUTE - used - 1 };
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parse<T extends z.ZodType>(schema: T, value: unknown, what: string): z.output<T> {
  const r = schema.safeParse(value);
  if (!r.success) {
    const detail = r.error.issues.map((i) => `${i.path.join('.') || what}: ${i.message}`).join('; ');
    throw new ApiError(400, 'invalid_request', `Bad ${what}. ${detail}`);
  }
  return r.data;
}

function iso(v: unknown): string | null {
  return toDate(v)?.toISOString() ?? null;
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const int = (v: unknown): number | null => (typeof v === 'number' && Number.isInteger(v) ? v : null);
const str = (v: unknown): string | null => (typeof v === 'string' ? v : null);

interface Cursor {
  t: number;
  id: string;
}

function encodeCursor(c: Cursor): string {
  return Buffer.from(JSON.stringify(c), 'utf8').toString('base64url');
}

function decodeCursor(raw: string | undefined): Cursor | null {
  if (raw === undefined) return null;
  try {
    const c = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8')) as Cursor;
    if (Number.isFinite(c.t) && typeof c.id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(c.id)) return c;
  } catch {
    // fall through
  }
  throw new ApiError(400, 'invalid_request', 'The cursor is not valid. Use `nextCursor` from the previous page.');
}

function civil(date: string) {
  const [year, month, day] = date.split('-').map(Number);
  return { year, month, day };
}

/** Applies from, to and cursor to a newest-first query on startedAt. */
async function rangedQuery(
  deps: Deps,
  base: Query,
  uid: string,
  q: { from?: string; to?: string; cursor?: string },
): Promise<Query> {
  const cursor = decodeCursor(q.cursor);
  let query = base;
  if (q.from || q.to) {
    const tz = userTimeZone((await deps.db.doc(`users/${uid}`).get()).data());
    if (q.from && q.to && q.from > q.to) throw new ApiError(400, 'invalid_request', '`from` is after `to`.');
    if (q.from) query = query.where('startedAt', '>=', Timestamp.fromDate(dayBounds(civil(q.from), tz).start));
    if (q.to) query = query.where('startedAt', '<', Timestamp.fromDate(dayBounds(civil(q.to), tz).end));
  }
  query = query.orderBy('startedAt', 'desc').orderBy(FieldPath.documentId(), 'desc');
  if (cursor) query = query.startAfter(Timestamp.fromMillis(cursor.t), cursor.id);
  return query;
}

function cursorOf(doc: FirebaseFirestore.QueryDocumentSnapshot): string {
  return encodeCursor({ t: toDate(doc.get('startedAt'))?.getTime() ?? 0, id: doc.id });
}

function totalsOf(s: FirebaseFirestore.DocumentData): { setCount: number; totalVolumeKg: number } {
  const stored = s.status === 'stamped' && typeof s.setCount === 'number' && typeof s.totalVolume === 'number';
  if (stored) return { setCount: s.setCount, totalVolumeKg: s.totalVolume };
  const t = sessionTotals(sanitizeExercises(s.exercises));
  return { setCount: t.setCount, totalVolumeKg: t.totalVolume };
}

function weekdays(raw: unknown): (typeof WEEKDAYS)[number][] {
  if (!Array.isArray(raw)) return [];
  const out = new Set<(typeof WEEKDAYS)[number]>();
  for (const d of raw) {
    // Stored either as `mon`...`sun` or as ISO weekday numbers 1 (Monday) to 7.
    if (typeof d === 'string' && (WEEKDAYS as readonly string[]).includes(d.toLowerCase())) out.add(d.toLowerCase() as (typeof WEEKDAYS)[number]);
    else if (typeof d === 'number' && Number.isInteger(d) && d >= 1 && d <= 7) out.add(WEEKDAYS[d - 1]);
  }
  return WEEKDAYS.filter((d) => out.has(d));
}

function currentWeek(deps: Deps, u: FirebaseFirestore.DocumentData | undefined) {
  const tz = userTimeZone(u);
  const key = weekKey(deps.now(), tz);
  const state = readStreakState(u?.streakState);
  return state && state.weekKey === key
    ? { weekKey: key, sessions: state.weekCount, goal: state.weekGoal }
    : { weekKey: key, sessions: 0, goal: clampGoal(u?.goalPerWeek) };
}

const notFound = (what: string) => new ApiError(404, 'not_found', `No such ${what} for this owner.`);

// ---------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------

type Handler = (deps: Deps, caller: Caller, params: Record<string, string>, query: Record<string, unknown>) => Promise<unknown>;

async function getMe(deps: Deps, caller: Caller) {
  const u = (await deps.db.doc(`users/${caller.uid}`).get()).data();
  if (!u) throw notFound('profile');
  return {
    displayName: str(u.displayName),
    units: u.units === 'lb' ? 'lb' : 'kg',
    timezone: userTimeZone(u),
    goalPerWeek: currentWeek(deps, u).goal,
    gymDays: weekdays(u.gymDays),
  };
}

async function getStats(deps: Deps, caller: Caller) {
  const db: Firestore = deps.db;
  const [userSnap, agg] = await Promise.all([
    db.doc(`users/${caller.uid}`).get(),
    db
      .collection(`users/${caller.uid}/sessions`)
      .where('status', '==', 'stamped')
      .aggregate({ total: AggregateField.sum('totalVolume') })
      .get(),
  ]);
  const u = userSnap.data();
  return {
    streakWeeks: int(u?.streakWeeks) ?? 0,
    longestStreak: int(u?.longestStreak) ?? 0,
    passWeeks: int(u?.passWeeks) ?? 0,
    proofCount: int(u?.proofCount) ?? 0,
    thisWeek: currentWeek(deps, u),
    totalVolumeKg: Math.round((agg.data().total ?? 0) * 10) / 10,
  };
}

async function listSessions(deps: Deps, caller: Caller, _p: Record<string, string>, query: Record<string, unknown>) {
  const base = deps.db.collection(`users/${caller.uid}/sessions`).where('status', 'in', LISTED_STATUSES);
  const q = await rangedQuery(deps, base, caller.uid, query);
  const snap = await q.limit(PAGE_SIZE + 1).get();
  const docs = snap.docs.slice(0, PAGE_SIZE);
  return {
    sessions: docs.map((d) => {
      const s = d.data();
      return {
        id: d.id,
        status: s.status,
        routineName: str(s.routineName),
        startedAt: iso(s.startedAt),
        durationSec: int(s.durationSec),
        timezone: str(s.timezone),
        weekKey: str(s.weekKey),
        ...totalsOf(s),
        proofNumber: int(s.proofNumber),
      };
    }),
    nextCursor: snap.docs.length > PAGE_SIZE ? cursorOf(docs[docs.length - 1]) : null,
  };
}

function setOut(set: LoggedSet) {
  return {
    n: int(set.n),
    type: str(set.type),
    weightKg: num(set.weight),
    reps: int(set.reps),
    done: set.done === true,
    rpe: num(set.rpe),
  };
}

async function readableSession(deps: Deps, uid: string, id: string) {
  const snap = await deps.db.doc(`users/${uid}/sessions/${id}`).get();
  const s = snap.data();
  if (!s || !LISTED_STATUSES.includes(s.status) || !toDate(s.startedAt)) throw notFound('session');
  return s;
}

async function getSession(deps: Deps, caller: Caller, params: Record<string, string>) {
  const s = await readableSession(deps, caller.uid, params.id);
  const out: Record<string, unknown> = {
    id: params.id,
    status: s.status,
    routineId: str(s.routineId),
    routineName: str(s.routineName),
    startedAt: iso(s.startedAt),
    endedAt: iso(s.endedAt),
    stampedAt: iso(s.stampedAt),
    durationSec: int(s.durationSec),
    timezone: str(s.timezone),
    weekKey: str(s.weekKey),
    proofNumber: int(s.proofNumber),
    exercises: sanitizeExercises(s.exercises).map((e) => ({
      exerciseId: e.exerciseId,
      name: str(e.name),
      sets: (e.sets ?? []).filter((x) => x && typeof x === 'object').map(setOut),
    })),
    ...totalsOf(s),
    newBests: Array.isArray(s.newBests) ? s.newBests.filter((x: unknown) => typeof x === 'string') : [],
  };
  return out;
}

async function getExerciseHistory(deps: Deps, caller: Caller, params: Record<string, string>, query: Record<string, unknown>) {
  const exId = params.id;
  const statsSnap = await deps.db.doc(`users/${caller.uid}/exerciseStats/${exId}`).get();
  const st = statsSnap.data();
  if (!st) throw notFound('exercise');

  const base = deps.db.collection(`users/${caller.uid}/sessions`).where('status', '==', 'stamped');
  let q = await rangedQuery(deps, base, caller.uid, query);
  const history: Array<{ sessionId: string; startedAt: string | null; e1rmKg: number; sets: Array<{ type: string | null; weightKg: number; reps: number }> }> = [];
  let name: string | null = null;
  let scanned = 0;
  let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  let exhausted = false;

  outer: while (history.length < PAGE_SIZE && scanned < HISTORY_SCAN_LIMIT) {
    const batch = await q.limit(HISTORY_BATCH).get();
    for (const d of batch.docs) {
      lastDoc = d;
      scanned += 1;
      const mine = sanitizeExercises(d.get('exercises')).filter((e) => e.exerciseId === exId);
      const sets = mine.flatMap((e) => e.sets ?? []).filter((x) => x && typeof x === 'object' && x.done === true);
      if (sets.length > 0) {
        name ??= mine.map((e) => str(e.name)).find((n) => n !== null) ?? null;
        const best = sessionTotals(mine).perExercise.get(exId)?.bestE1rm ?? 0;
        history.push({
          sessionId: d.id,
          startedAt: iso(d.get('startedAt')),
          e1rmKg: best,
          sets: sets.map((x) => ({ type: str(x.type), weightKg: num(x.weight) ?? 0, reps: int(x.reps) ?? 0 })),
        });
      }
      if (history.length >= PAGE_SIZE || scanned >= HISTORY_SCAN_LIMIT) break outer;
    }
    if (batch.size < HISTORY_BATCH) {
      exhausted = true;
      break;
    }
    q = q.startAfter(batch.docs[batch.docs.length - 1]);
  }

  const bestSet = st.bestSet && typeof st.bestSet === 'object' ? st.bestSet : null;
  return {
    exerciseId: exId,
    name,
    bestSet: bestSet ? { weightKg: num(bestSet.weight) ?? 0, reps: int(bestSet.reps) ?? 0 } : null,
    bestE1rmKg: num(st.bestE1rm) ?? 0,
    lastPerformedAt: iso(st.lastPerformedAt),
    history,
    nextCursor: !exhausted && lastDoc ? cursorOf(lastDoc) : null,
  };
}

const HANDLERS: Record<RouteId, Handler> = {
  getMe,
  getStats,
  listSessions,
  getSession,
  getExerciseHistory,
};

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

const JSON_HEADERS = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' };

let openApiCache: unknown;
export function openApiDocument(): unknown {
  openApiCache ??= buildOpenApi();
  return openApiCache;
}

function errorResponse(e: ApiError): ApiResponse {
  return {
    status: e.status,
    headers: { ...JSON_HEADERS, ...e.headers },
    body: { error: { code: e.code, message: e.message, ...e.extra } },
  };
}

export async function handleApi(deps: Deps, req: ApiRequest): Promise<ApiResponse> {
  const started = Date.now();
  const path = normalizePath(req.path);
  const method = req.method.toUpperCase();
  let caller: Caller | undefined;
  let routeName = 'unmatched';
  let res: ApiResponse;

  try {
    if (path === '/v1/openapi.json') {
      routeName = 'getOpenApi';
      if (method !== 'GET' && method !== 'HEAD') throw new ApiError(405, 'method_not_allowed', 'Only GET is supported.', {}, { Allow: 'GET' });
      res = { status: 200, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'public, max-age=300' }, body: openApiDocument() };
    } else {
      const m = match(path);
      if (!m) throw new ApiError(404, 'not_found', 'No such endpoint. See /v1/openapi.json.');
      routeName = m.route.operationId;
      if (method !== 'GET') throw new ApiError(405, 'method_not_allowed', 'The agent API is read-only. Only GET is supported.', {}, { Allow: 'GET' });

      caller = await authenticate(deps, req.headers);
      if (!caller.scopes.has(m.route.scope)) {
        throw new ApiError(403, 'insufficient_scope', `This token does not have ${m.route.scope}.`, { requiredScope: m.route.scope }, {
          'WWW-Authenticate': `Bearer realm="pgym", error="insufficient_scope", scope="${m.route.scope}"`,
        });
      }
      const params = m.route.params ? parse(m.route.params, m.params, 'path') : {};
      const query = m.route.query ? parse(m.route.query, req.query ?? {}, 'query') : {};
      const raw = await HANDLERS[m.route.operationId](deps, caller, params as Record<string, string>, query as Record<string, unknown>);
      const body = m.route.response.parse(raw);
      res = {
        status: 200,
        headers: {
          ...JSON_HEADERS,
          'X-RateLimit-Limit': String(RATE_LIMIT_PER_MINUTE),
          'X-RateLimit-Remaining': String(caller.remaining),
        },
        body,
      };
    }
  } catch (err) {
    if (err instanceof ApiError) {
      res = errorResponse(err);
    } else {
      deps.log.warn('api error', { route: routeName, uid: caller?.uid, tokenId: caller?.tokenId, error: String(err) });
      res = errorResponse(new ApiError(500, 'server_error', 'Something went wrong on our side. Retry once after a short wait.'));
    }
  }

  deps.log.info('api', {
    method,
    route: routeName,
    status: res.status,
    code: (res.body as { error?: { code?: string } }).error?.code,
    uid: caller?.uid,
    tokenId: caller?.tokenId,
    ms: Date.now() - started,
  });
  return res;
}
