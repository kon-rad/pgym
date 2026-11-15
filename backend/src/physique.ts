/**
 * analyzePhysique: the private, opt-in, 18+ physique score (architecture note,
 * "Flow: physique analysis"; design note, "The physique score").
 *
 * The handler takes its storage through `PhysiqueRepo` (Firestore in
 * production, see physiqueRepo.ts; in memory in the unit tests), the photo
 * through `PhotoStore`, and the model through `VisionModel`. Nothing here
 * imports firebase-admin, so every rule below is tested without an emulator.
 */
import { z } from 'zod';
import { ID_PATTERN, MAX_UPLOAD_BYTES, PHOTO_CONTENT_TYPE, photoKey, type PhotoStore } from './photoStore';
import {
  MODEL_REFUSAL_REASONS,
  PHYSIQUE_PROMPT,
  PHYSIQUE_RESPONSE_SCHEMA,
  PROMPT_VERSION,
  TIP_MAX_CHARS,
  type ModelRefusalReason,
} from './physiquePrompt';
import { dayBounds, isValidTimeZone, localDate } from './streak';
import type { TokenUsage, VisionModel } from './visionModel';

export const ADULT_AGE = 18;
/** Model calls per user per local calendar day. */
export const DAILY_LIMIT = 3;
/** How many earlier scores the new one is smoothed against. */
export const SMOOTHING_WINDOW = 3;
/** Weight of the new photo against each earlier score. 2 means 40 % with a full window of 3. */
export const NEW_SCORE_WEIGHT = 2;

/**
 * Everything that can be stored as `physique.refusedReason`. The model's five
 * reasons map to the copy deck's no-score lines ("unreadable" is "Too dark to
 * read"); `failure` is "Scoring did not work this time."; `daily_limit` has no
 * line yet (see the PR's follow-ups).
 */
export type RefusedReason = ModelRefusalReason | 'failure' | 'daily_limit';

export interface Logger {
  info(message: string, data?: Record<string, unknown>): void;
  warn(message: string, data?: Record<string, unknown>): void;
}

/**
 * What is written to `users/{uid}/sessions/{sessionId}.physique`. Either a
 * score (with an optional tip) or a refusedReason, never both.
 * `rawScore` is the clamped model score before smoothing; it is an addition to
 * the architecture's field list so later smoothing uses raw numbers, not
 * already-smoothed ones.
 */
export interface PhysiqueRecord {
  score?: number;
  rawScore?: number;
  tip?: string;
  model?: string;
  analyzedAt: Date;
  refusedReason?: RefusedReason;
}

export interface PhysiqueUser {
  physiqueConsent?: unknown;
  birthYear?: unknown;
  timezone?: unknown;
}

export interface PhysiqueSession {
  status?: unknown;
  physique?: unknown;
}

export type ClaimResult = 'claimed' | 'already_analyzed' | 'daily_limit';

export interface PhysiqueRepo {
  getUser(uid: string): Promise<PhysiqueUser | null>;
  getSession(uid: string, sessionId: string): Promise<PhysiqueSession | null>;
  /**
   * Atomically reserve this session's one analysis. Returns `already_analyzed`
   * when the session has any `physique` value; `daily_limit` when `limit`
   * sessions already have a model call (`physique.model` set) with
   * `physique.analyzedAt` at or after `dayStart`. Otherwise writes `record`
   * (a pessimistic failure, so a crash mid-call reads as "did not work") and
   * returns `claimed`.
   */
  claim(uid: string, sessionId: string, opts: { dayStart: Date; limit: number; record: PhysiqueRecord }): Promise<ClaimResult>;
  /** Raw scores of the user's most recent scored sessions, newest first, excluding `excludeSessionId`. */
  recentRawScores(uid: string, excludeSessionId: string, count: number): Promise<number[]>;
  write(uid: string, sessionId: string, record: PhysiqueRecord): Promise<void>;
}

export interface PhysiqueDeps {
  repo: PhysiqueRepo;
  store: Pick<PhotoStore, 'getBytes'>;
  /** Null while no model ID is pinned (physiquePrompt.ts). */
  model: VisionModel | null;
  now: () => Date;
  log: Logger;
}

export type AnalyzeOutcome =
  | { status: 'skipped'; reason: 'no_user' | 'no_consent' | 'under_18' | 'no_session' | 'not_stamped' | 'already_analyzed' }
  | { status: 'refused'; refusedReason: RefusedReason; modelCalled: boolean }
  | { status: 'scored'; score: number; rawScore: number; tip: string | null; usage: TokenUsage };

// ---------------------------------------------------------------------------
// Pure rules
// ---------------------------------------------------------------------------

/**
 * Year of birth only: someone born in year Y is treated as 18 from 1 January
 * of Y + 19, the earliest date they are certainly 18.
 */
export function isAdult(birthYear: unknown, now: Date): boolean {
  return typeof birthYear === 'number' && Number.isInteger(birthYear) && now.getUTCFullYear() - birthYear > ADULT_AGE;
}

/** Round and clamp to 0..100. */
export function clampScore(n: number): number {
  return Math.min(100, Math.max(0, Math.round(n)));
}

/**
 * Collapse whitespace and cut to `max` characters (code points, so an emoji
 * is never split). A long tip is cut at the last word break and given a full
 * stop, so it still reads as a sentence.
 */
export function cutTip(tip: string, max = TIP_MAX_CHARS): string {
  const clean = tip.replace(/\s+/g, ' ').trim();
  const chars = Array.from(clean);
  if (chars.length <= max) return clean;
  const head = chars.slice(0, max - 1).join('');
  const lastSpace = head.lastIndexOf(' ');
  const base = lastSpace >= max / 2 ? head.slice(0, lastSpace) : head;
  return `${base.replace(/[\s,;:.-]+$/, '')}.`;
}

/** Words from the copy deck's server check, matched as whole words. */
const BANNED_TIP_PATTERN =
  /\b(weight loss|lose weight|fat|fats|diet|diets|dieting|calorie|calories|skinny|lean out|cut|cutting|bulk|bulking|supplement|supplements|doctor|ugly|attractive)\b/i;
const EMOJI_PATTERN = /\p{Extended_Pictographic}/u;

/**
 * The copy deck's server check: no exclamation mark, no emoji, no banned word.
 * A rejected tip is dropped; the score still shows.
 */
export function tipAllowed(tip: string): boolean {
  if (tip.length === 0) return false;
  if (tip.includes('!')) return false;
  if (EMOJI_PATTERN.test(tip)) return false;
  return !BANNED_TIP_PATTERN.test(tip);
}

/**
 * Weighted mean of the new score and up to SMOOTHING_WINDOW earlier raw
 * scores (newest first), so one photo in bad light cannot swing the number.
 */
export function smoothScore(raw: number, earlier: number[]): number {
  const prev = earlier.filter((n) => Number.isFinite(n)).slice(0, SMOOTHING_WINDOW);
  if (prev.length === 0) return clampScore(raw);
  const sum = prev.reduce((a, b) => a + b, 0);
  return clampScore((NEW_SCORE_WEIGHT * raw + sum) / (NEW_SCORE_WEIGHT + prev.length));
}

const ModelReply = z.object({
  usable: z.boolean(),
  refusedReason: z.string().nullish(),
  score: z.number().nullish(),
  tip: z.string().nullish(),
});

export type ParsedReply =
  | { kind: 'usable'; score: number; tip: string | null }
  | { kind: 'refused'; reason: ModelRefusalReason }
  | { kind: 'malformed'; problem: string };

/**
 * Validate the model's reply. Never trusts the schema to have been followed:
 * anything that is not a clear refusal or a finite score is `malformed`.
 * The score is clamped and the tip cut and checked here.
 */
export function parseModelReply(text: string): ParsedReply {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    return { kind: 'malformed', problem: 'not JSON' };
  }
  const parsed = ModelReply.safeParse(json);
  if (!parsed.success) return { kind: 'malformed', problem: 'wrong shape' };
  const r = parsed.data;
  if (!r.usable) {
    const reason = (MODEL_REFUSAL_REASONS as readonly string[]).includes(r.refusedReason ?? '')
      ? (r.refusedReason as ModelRefusalReason)
      : 'unreadable';
    return { kind: 'refused', reason };
  }
  if (typeof r.score !== 'number' || !Number.isFinite(r.score)) return { kind: 'malformed', problem: 'no score' };
  let tip: string | null = null;
  if (typeof r.tip === 'string') {
    const cut = cutTip(r.tip);
    tip = tipAllowed(cut) ? cut : null;
  }
  return { kind: 'usable', score: clampScore(r.score), tip };
}

/** Start of the user's local calendar day; UTC when the stored zone is missing or unknown. */
export function localDayStart(now: Date, timeZone: unknown): Date {
  const tz = isValidTimeZone(timeZone) ? timeZone : 'UTC';
  return dayBounds(localDate(now, tz), tz).start;
}

/** Task payload: `{uid, sessionId}`, both plain IDs. */
export function readTask(data: unknown): { uid: string; sessionId: string } | null {
  const d = data as { uid?: unknown; sessionId?: unknown } | null;
  if (typeof d?.uid !== 'string' || typeof d?.sessionId !== 'string') return null;
  if (!ID_PATTERN.test(d.uid) || !ID_PATTERN.test(d.sessionId)) return null;
  return { uid: d.uid, sessionId: d.sessionId };
}

/** Cloud Tasks ID for a session's analysis, so a double enqueue is dropped by the queue. */
export function physiqueTaskId(uid: string, sessionId: string): string {
  return `physique-${uid}-${sessionId}`;
}

// ---------------------------------------------------------------------------
// The handler
// ---------------------------------------------------------------------------

/**
 * One analysis for one stamped session. Order matters:
 * 1. Gates that cost nothing: user exists, consent on, 18 or over, session stamped, not analyzed yet.
 * 2. Read the photo. A storage error throws, so the task queue retries.
 * 3. Claim the session's one analysis and a slot in today's limit, atomically.
 * 4. Call the model. Any error from here on writes refusedReason and no score.
 */
export async function analyzePhysique(deps: PhysiqueDeps, data: unknown): Promise<AnalyzeOutcome> {
  const task = readTask(data);
  if (!task) {
    deps.log.warn('analyzePhysique bad task payload');
    return { status: 'skipped', reason: 'no_session' };
  }
  const { uid, sessionId } = task;
  const now = deps.now();
  const skip = (reason: Extract<AnalyzeOutcome, { status: 'skipped' }>['reason']): AnalyzeOutcome => {
    deps.log.info('analyzePhysique skipped', { uid, sessionId, reason });
    return { status: 'skipped', reason };
  };

  const user = await deps.repo.getUser(uid);
  if (!user) return skip('no_user');
  // Consent and age are checked again here, not only at enqueue: either can change in between.
  if (user.physiqueConsent !== true) return skip('no_consent');
  if (!isAdult(user.birthYear, now)) return skip('under_18');

  const session = await deps.repo.getSession(uid, sessionId);
  if (!session) return skip('no_session');
  if (session.status !== 'stamped') return skip('not_stamped');
  if (session.physique !== undefined && session.physique !== null) return skip('already_analyzed');

  const refuse = async (refusedReason: RefusedReason, modelCalled: boolean, extra: Record<string, unknown> = {}): Promise<AnalyzeOutcome> => {
    await deps.repo.write(uid, sessionId, {
      refusedReason,
      analyzedAt: now,
      ...(modelCalled && deps.model ? { model: deps.model.modelId } : {}),
    });
    deps.log.info('analyzePhysique refused', { uid, sessionId, refusedReason, modelCalled, promptVersion: PROMPT_VERSION, ...extra });
    return { status: 'refused', refusedReason, modelCalled };
  };

  if (!deps.model) {
    deps.log.warn('analyzePhysique has no pinned model ID', { uid, sessionId });
    return refuse('failure', false);
  }

  const image = await deps.store.getBytes(photoKey(uid, sessionId), MAX_UPLOAD_BYTES);

  const claim = await deps.repo.claim(uid, sessionId, {
    dayStart: localDayStart(now, user.timezone),
    limit: DAILY_LIMIT,
    record: { refusedReason: 'failure', model: deps.model.modelId, analyzedAt: now },
  });
  if (claim === 'already_analyzed') return skip('already_analyzed');
  if (claim === 'daily_limit') return refuse('daily_limit', false);

  let replyText: string;
  let usage: TokenUsage;
  let finishReason: string | undefined;
  try {
    const res = await deps.model.analyze({
      prompt: PHYSIQUE_PROMPT,
      responseSchema: PHYSIQUE_RESPONSE_SCHEMA,
      image,
      mimeType: PHOTO_CONTENT_TYPE,
    });
    replyText = res.text;
    usage = res.usage;
    finishReason = res.finishReason;
  } catch (err) {
    return refuse('failure', true, { error: err instanceof Error ? err.message : String(err) });
  }

  // Tokens only: the photo and the model's text are never logged.
  const usageLog = { inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, finishReason };
  const reply = parseModelReply(replyText);
  if (reply.kind === 'malformed') return refuse('failure', true, { problem: reply.problem, ...usageLog });
  if (reply.kind === 'refused') return refuse(reply.reason, true, usageLog);

  const earlier = await deps.repo.recentRawScores(uid, sessionId, SMOOTHING_WINDOW);
  const score = smoothScore(reply.score, earlier);
  await deps.repo.write(uid, sessionId, {
    score,
    rawScore: reply.score,
    ...(reply.tip ? { tip: reply.tip } : {}),
    model: deps.model.modelId,
    analyzedAt: now,
  });
  deps.log.info('analyzePhysique scored', {
    uid,
    sessionId,
    score,
    rawScore: reply.score,
    smoothedOver: earlier.length,
    tipKept: reply.tip !== null,
    model: deps.model.modelId,
    promptVersion: PROMPT_VERSION,
    ...usageLog,
  });
  return { status: 'scored', score, rawScore: reply.score, tip: reply.tip, usage };
}
