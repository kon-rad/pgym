/**
 * Weekly streak logic. Pure: no Firestore, no clock. Every input is passed in.
 *
 * Rules (pgym-design.md, "Streak with slack" and "Commitment"):
 * - The streak counts weeks, not days. A week runs Monday 00:00 to Sunday 24:00
 *   in the user's timezone and is keyed ISO-style, for example `2026-W46`.
 * - A week is hit when the number of stamped sessions in it reaches the goal
 *   that was locked when the week started. Changing the goal mid-week only
 *   changes the goal of the following week.
 * - One pass week is earned for every 4 weeks hit. A missed week spends a pass
 *   automatically and the streak survives (without growing). With no pass
 *   left, a missed week breaks the streak.
 * - A session counts for the day it started, so a session started on Sunday
 *   23:50 and stamped on Monday 00:20 counts for the week that just ended.
 *
 * The stored state keeps the closed weeks separately from the open week, so a
 * stamp or a delete only changes `weekCount`, and the numbers the user sees
 * are derived by `view()`.
 */

export const WEEKS_PER_PASS = 4;
export const MIN_GOAL = 2;
export const MAX_GOAL = 6;

export interface StreakState {
  /** The open week, for example `2026-W46`. */
  weekKey: string;
  /** The goal locked for the open week. */
  weekGoal: number;
  /** Stamped sessions counted in the open week. */
  weekCount: number;
  /** Streak length over closed weeks only. */
  streakClosed: number;
  /** Longest streak over closed weeks only. */
  longestClosed: number;
  /** Pass weeks banked over closed weeks only. */
  passClosed: number;
  /** Weeks hit since the last pass was earned (0 to WEEKS_PER_PASS - 1). */
  hitsTowardPass: number;
}

export interface StreakView {
  streakWeeks: number;
  longestStreak: number;
  passWeeks: number;
  weekHit: boolean;
}

export type WeekOutcome = 'hit' | 'pass' | 'broken' | 'none';

// ---------------------------------------------------------------------------
// Calendar helpers
// ---------------------------------------------------------------------------

export interface CivilDate {
  year: number;
  month: number; // 1-12
  day: number;
}

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let f = formatterCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
    });
    formatterCache.set(timeZone, f);
  }
  return f;
}

/** True when `timeZone` is an IANA zone the runtime knows. */
export function isValidTimeZone(timeZone: unknown): timeZone is string {
  if (typeof timeZone !== 'string' || timeZone.length === 0 || timeZone.length > 64) return false;
  try {
    formatterFor(timeZone);
    return true;
  } catch {
    return false;
  }
}

/** Wall-clock fields of `instant` in `timeZone`. */
function wallClock(instant: Date, timeZone: string) {
  const parts = formatterFor(timeZone).formatToParts(instant);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
  return {
    year: get('year'),
    month: get('month'),
    day: get('day'),
    hour: get('hour'),
    minute: get('minute'),
    second: get('second'),
  };
}

/** Offset of `timeZone` from UTC at `instant`, in milliseconds (west is negative). */
function offsetMs(instant: Date, timeZone: string): number {
  const w = wallClock(instant, timeZone);
  const asUtc = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
  const truncated = instant.getTime() - instant.getUTCMilliseconds();
  return asUtc - truncated;
}

/** The instant of local midnight at the start of `date` in `timeZone`. */
function localMidnight(date: CivilDate, timeZone: string): Date {
  const guess = Date.UTC(date.year, date.month - 1, date.day);
  let instant = guess - offsetMs(new Date(guess), timeZone);
  // Second pass corrects the guess when a DST change lies between the two.
  instant = guess - offsetMs(new Date(instant), timeZone);
  return new Date(instant);
}

/** The calendar date of `instant` in `timeZone`. */
export function localDate(instant: Date, timeZone: string): CivilDate {
  const w = wallClock(instant, timeZone);
  return { year: w.year, month: w.month, day: w.day };
}

function addDays(date: CivilDate, days: number): CivilDate {
  const d = new Date(Date.UTC(date.year, date.month - 1, date.day + days));
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

/**
 * The instants local `date` starts and the next day starts in `timeZone`.
 * The agent API reads `from` and `to` dates this way, both ends inclusive.
 */
export function dayBounds(date: CivilDate, timeZone: string): { start: Date; end: Date } {
  return { start: localMidnight(date, timeZone), end: localMidnight(addDays(date, 1), timeZone) };
}

/** ISO weekday, Monday = 1 ... Sunday = 7. */
function isoWeekday(date: CivilDate): number {
  const dow = new Date(Date.UTC(date.year, date.month - 1, date.day)).getUTCDay();
  return dow === 0 ? 7 : dow;
}

function weekKeyOfDate(date: CivilDate): string {
  // ISO 8601: the week belongs to the year that holds its Thursday.
  const thursday = addDays(date, 4 - isoWeekday(date));
  const jan1 = Date.UTC(thursday.year, 0, 1);
  const dayOfYear = Math.floor((Date.UTC(thursday.year, thursday.month - 1, thursday.day) - jan1) / 86_400_000);
  const week = Math.floor(dayOfYear / 7) + 1;
  return `${thursday.year}-W${String(week).padStart(2, '0')}`;
}

const WEEK_KEY = /^(\d{4})-W(\d{2})$/;

/** The Monday that starts `weekKey`. */
function mondayOf(weekKey: string): CivilDate {
  const m = WEEK_KEY.exec(weekKey);
  if (!m) throw new Error(`bad week key: ${weekKey}`);
  const year = Number(m[1]);
  const week = Number(m[2]);
  // January 4th is always in ISO week 1.
  const jan4: CivilDate = { year, month: 1, day: 4 };
  const week1Monday = addDays(jan4, 1 - isoWeekday(jan4));
  return addDays(week1Monday, (week - 1) * 7);
}

/** The week key of `instant` in `timeZone`, for example `2026-W46`. */
export function weekKey(instant: Date, timeZone: string): string {
  return weekKeyOfDate(localDate(instant, timeZone));
}

/** The week a session counts for: the week of the day it started. */
export function sessionWeekKey(startedAt: Date, timeZone: string): string {
  return weekKey(startedAt, timeZone);
}

export function nextWeekKey(key: string): string {
  return weekKeyOfDate(addDays(mondayOf(key), 7));
}

/** Negative when a is before b. Week keys are zero-padded, so string order is time order. */
export function compareWeekKeys(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** The instant the week ends (next Monday 00:00 local) in `timeZone`. */
export function weekEndsAt(key: string, timeZone: string): Date {
  return localMidnight(addDays(mondayOf(key), 7), timeZone);
}

// ---------------------------------------------------------------------------
// Streak state
// ---------------------------------------------------------------------------

export function clampGoal(goal: unknown): number {
  const n = typeof goal === 'number' && Number.isFinite(goal) ? Math.round(goal) : MIN_GOAL;
  return Math.min(MAX_GOAL, Math.max(MIN_GOAL, n));
}

export function initialState(key: string, goal: number): StreakState {
  return {
    weekKey: key,
    weekGoal: clampGoal(goal),
    weekCount: 0,
    streakClosed: 0,
    longestClosed: 0,
    passClosed: 0,
    hitsTowardPass: 0,
  };
}

/** The numbers the user sees, counting the open week once it is hit. */
export function view(state: StreakState): StreakView {
  const weekHit = state.weekCount >= state.weekGoal;
  if (!weekHit) {
    return {
      streakWeeks: state.streakClosed,
      longestStreak: state.longestClosed,
      passWeeks: state.passClosed,
      weekHit,
    };
  }
  const streakWeeks = state.streakClosed + 1;
  const earnsPass = state.hitsTowardPass + 1 >= WEEKS_PER_PASS;
  return {
    streakWeeks,
    longestStreak: Math.max(state.longestClosed, streakWeeks),
    passWeeks: state.passClosed + (earnsPass ? 1 : 0),
    weekHit,
  };
}

/** Close the open week and open the next one with `nextGoal` locked. */
export function closeWeek(state: StreakState, nextGoal: number): { state: StreakState; outcome: WeekOutcome } {
  let { streakClosed, longestClosed, passClosed, hitsTowardPass } = state;
  let outcome: WeekOutcome;
  if (state.weekCount >= state.weekGoal) {
    outcome = 'hit';
    streakClosed += 1;
    longestClosed = Math.max(longestClosed, streakClosed);
    hitsTowardPass += 1;
    if (hitsTowardPass >= WEEKS_PER_PASS) {
      passClosed += 1;
      hitsTowardPass = 0;
    }
  } else if (streakClosed === 0) {
    outcome = 'none';
  } else if (passClosed > 0) {
    outcome = 'pass';
    passClosed -= 1;
  } else {
    outcome = 'broken';
    streakClosed = 0;
    hitsTowardPass = 0;
  }
  return {
    outcome,
    state: {
      weekKey: nextWeekKey(state.weekKey),
      weekGoal: clampGoal(nextGoal),
      weekCount: 0,
      streakClosed,
      longestClosed,
      passClosed,
      hitsTowardPass,
    },
  };
}

/** Upper bound on weeks closed in one call, so bad input cannot loop for ever. */
const MAX_ROLL_WEEKS = 5 * 53;

/**
 * Close weeks until `target` is the open week. Weeks in between had no
 * sessions. Each newly opened week locks `goal`, the user's current goal.
 */
export function rollTo(state: StreakState, target: string, goal: number): { state: StreakState; outcomes: WeekOutcome[] } {
  const outcomes: WeekOutcome[] = [];
  let s = state;
  if (compareWeekKeys(target, s.weekKey) <= 0) return { state: s, outcomes };
  let weeksBetween = 0;
  for (let k = s.weekKey; compareWeekKeys(k, target) < 0; k = nextWeekKey(k)) {
    weeksBetween += 1;
    if (weeksBetween > MAX_ROLL_WEEKS) break;
  }
  if (weeksBetween > MAX_ROLL_WEEKS) {
    // Gone for years: every pass is spent and the streak is broken either way.
    const fresh = initialState(target, goal);
    fresh.longestClosed = Math.max(s.longestClosed, s.weekCount >= s.weekGoal ? s.streakClosed + 1 : 0);
    return { state: fresh, outcomes: ['broken'] };
  }
  while (compareWeekKeys(s.weekKey, target) < 0) {
    const r = closeWeek(s, goal);
    outcomes.push(r.outcome);
    s = r.state;
  }
  return { state: s, outcomes };
}

export type SessionPlacement = 'counted' | 'late';

/**
 * Count one stamped session. `sessionWeek` is the week of the session's start.
 * A session from a week after the open one rolls the state forward first.
 * A session from a week already closed is `late` and does not change the streak.
 */
export function addSession(
  state: StreakState,
  sessionWeek: string,
  currentGoal: number,
): { state: StreakState; placement: SessionPlacement; outcomes: WeekOutcome[] } {
  if (compareWeekKeys(sessionWeek, state.weekKey) < 0) {
    return { state, placement: 'late', outcomes: [] };
  }
  const rolled = rollTo(state, sessionWeek, currentGoal);
  return {
    state: { ...rolled.state, weekCount: rolled.state.weekCount + 1 },
    placement: 'counted',
    outcomes: rolled.outcomes,
  };
}

/** Uncount one deleted stamped session. Only the open week can still change. */
export function removeSession(state: StreakState, sessionWeek: string): StreakState {
  if (sessionWeek !== state.weekKey) return state;
  return { ...state, weekCount: Math.max(0, state.weekCount - 1) };
}
