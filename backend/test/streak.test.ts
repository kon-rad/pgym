import { describe, expect, it } from 'vitest';
import {
  addSession,
  initialState,
  rollTo,
  sessionWeekKey,
  view,
  weekEndsAt,
  weekKey,
  type StreakState,
} from '../src/streak';

// Calendar used below (ISO weeks, Monday first):
//   2026-W46 = Nov 9-15, W47 = Nov 16-22, W48 = Nov 23-29, W49 = Nov 30-Dec 6,
//   W50 = Dec 7-13, W51 = Dec 14-20, W52 = Dec 21-27, W53 = Dec 28-Jan 3,
//   2027-W01 = Jan 4-10.

describe('weekKey', () => {
  const cases: Array<[string, string, string, string]> = [
    ['Sunday noon UTC is still W46', '2026-11-15T12:00:00Z', 'UTC', '2026-W46'],
    ['Monday 00:00 UTC starts W47', '2026-11-16T00:00:00Z', 'UTC', '2026-W47'],
    ['Monday 03:00 UTC is Sunday evening in Los Angeles', '2026-11-16T03:00:00Z', 'America/Los_Angeles', '2026-W46'],
    ['Sunday 23:30 UTC is Monday morning in Tokyo', '2026-11-15T23:30:00Z', 'Asia/Tokyo', '2026-W47'],
    ['1 January 2027 belongs to 2026-W53', '2027-01-01T12:00:00Z', 'UTC', '2026-W53'],
    ['30 December 2024 belongs to 2025-W01', '2024-12-30T12:00:00Z', 'UTC', '2025-W01'],
  ];
  it.each(cases)('%s', (_name, iso, tz, expected) => {
    expect(weekKey(new Date(iso), tz)).toBe(expected);
  });

  it('a week ends at local midnight Monday, west of UTC', () => {
    expect(weekEndsAt('2026-W47', 'America/Los_Angeles').toISOString()).toBe('2026-11-23T08:00:00.000Z');
  });

  it('a week ends at local midnight across a DST change', () => {
    // US clocks go forward on Sunday 8 March 2026, so Monday 00:00 is EDT (UTC-4).
    expect(weekEndsAt('2026-W10', 'America/New_York').toISOString()).toBe('2026-03-09T04:00:00.000Z');
  });
});

type Event =
  | { session: string } // a stamped session, by its start instant
  | { setGoal: number } // the user edits goalPerWeek
  | { rollAt: string }; // rollWeek runs at this instant

interface Scenario {
  name: string;
  timezone: string;
  goal: number;
  /** The instant the user's first week opens. */
  start: string;
  events: Event[];
  expected: { streakWeeks: number; longestStreak: number; passWeeks: number; weekKey?: string; weekCount?: number };
}

/** n sessions on consecutive days from `monday` (YYYY-MM-DD) at 18:00 UTC. */
function week(monday: string, n: number): Event[] {
  const base = new Date(`${monday}T18:00:00Z`).getTime();
  return Array.from({ length: n }, (_, i) => ({ session: new Date(base + i * 86_400_000).toISOString() }));
}

/** `count` consecutive weeks from `monday`, each with `perWeek` sessions. */
function weeks(monday: string, count: number, perWeek: number): Event[] {
  const base = new Date(`${monday}T00:00:00Z`).getTime();
  return Array.from({ length: count }, (_, i) =>
    week(new Date(base + i * 7 * 86_400_000).toISOString().slice(0, 10), perWeek),
  ).flat();
}

function simulate(s: Scenario): { state: StreakState } {
  let goal = s.goal;
  let state = initialState(weekKey(new Date(s.start), s.timezone), goal);
  for (const e of s.events) {
    if ('session' in e) state = addSession(state, sessionWeekKey(new Date(e.session), s.timezone), goal).state;
    else if ('setGoal' in e) goal = e.setGoal;
    else state = rollTo(state, weekKey(new Date(e.rollAt), s.timezone), goal).state;
  }
  return { state };
}

const W47 = '2026-11-16';
const START = '2026-11-16T08:00:00Z';

const scenarios: Scenario[] = [
  {
    name: 'a new user with no sessions has no streak',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: [],
    expected: { streakWeeks: 0, longestStreak: 0, passWeeks: 0, weekKey: '2026-W47' },
  },
  {
    name: 'reaching the goal counts the week at once, before the week ends',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: week(W47, 3),
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekCount: 3 },
  },
  {
    name: 'two sessions against a goal of three is not a hit',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: week(W47, 2),
    expected: { streakWeeks: 0, longestStreak: 0, passWeeks: 0 },
  },
  {
    name: 'a hit week stays counted after the week rolls',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: [...week(W47, 3), { rollAt: '2026-11-23T12:00:00Z' }],
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekKey: '2026-W48', weekCount: 0 },
  },
  {
    name: 'a missed week with no pass breaks the streak but keeps the longest',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: [...weeks(W47, 2, 3), ...week('2026-11-30', 1), { rollAt: '2026-12-07T12:00:00Z' }],
    expected: { streakWeeks: 0, longestStreak: 2, passWeeks: 0, weekKey: '2026-W50' },
  },
  {
    name: 'four weeks hit earn one pass week',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: weeks(W47, 4, 3),
    expected: { streakWeeks: 4, longestStreak: 4, passWeeks: 1 },
  },
  {
    name: 'eight weeks hit earn two pass weeks',
    timezone: 'UTC',
    goal: 2,
    start: START,
    events: weeks(W47, 8, 2),
    expected: { streakWeeks: 8, longestStreak: 8, passWeeks: 2, weekKey: '2027-W01' },
  },
  {
    name: 'a missed week spends the pass automatically and the streak survives',
    timezone: 'UTC',
    goal: 3,
    start: START,
    // W47-W50 hit, W51 empty, rollWeek runs in W52.
    events: [...weeks(W47, 4, 3), { rollAt: '2026-12-21T12:00:00Z' }],
    expected: { streakWeeks: 4, longestStreak: 4, passWeeks: 0, weekKey: '2026-W52' },
  },
  {
    name: 'after the pass is spent the next missed week breaks the streak',
    timezone: 'UTC',
    goal: 3,
    start: START,
    // W51 spends the pass, W52 has no pass left.
    events: [...weeks(W47, 4, 3), { rollAt: '2026-12-28T12:00:00Z' }],
    expected: { streakWeeks: 0, longestStreak: 4, passWeeks: 0, weekKey: '2026-W53' },
  },
  {
    name: 'a goal lowered mid-week applies from the next week, not this one',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: [
      { session: '2026-11-16T18:00:00Z' },
      { setGoal: 2 },
      { session: '2026-11-18T18:00:00Z' }, // W47: 2 of the locked 3, not hit
      { rollAt: '2026-11-23T12:00:00Z' },
      ...week('2026-11-23', 2), // W48: 2 of the new 2, hit
    ],
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekKey: '2026-W48', weekCount: 2 },
  },
  {
    name: 'a goal raised mid-week does not take away a week already hit',
    timezone: 'UTC',
    goal: 2,
    start: START,
    events: [...week(W47, 2), { setGoal: 4 }, { rollAt: '2026-11-23T12:00:00Z' }, ...week('2026-11-23', 2)],
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekKey: '2026-W48', weekCount: 2 },
  },
  {
    name: 'west of UTC: Sunday 20:00 in Los Angeles counts for that week, though UTC is already Monday',
    timezone: 'America/Los_Angeles',
    goal: 2,
    start: '2026-11-16T16:00:00Z', // Monday 08:00 PST
    events: [
      { session: '2026-11-17T02:00:00Z' }, // Monday 18:00 PST
      { session: '2026-11-23T04:00:00Z' }, // Sunday 20:00 PST, Monday 04:00 UTC
    ],
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekKey: '2026-W47', weekCount: 2 },
  },
  {
    name: 'a session started before midnight counts for its start day (Tokyo)',
    timezone: 'Asia/Tokyo',
    goal: 2,
    start: '2026-11-16T00:00:00Z', // Monday 09:00 JST
    events: [
      { session: '2026-11-16T09:00:00Z' }, // Monday 18:00 JST
      { session: '2026-11-22T14:50:00Z' }, // Sunday 23:50 JST, stamped after midnight
    ],
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekKey: '2026-W47' },
  },
  {
    name: 'a late session from a week already closed does not change the streak',
    timezone: 'UTC',
    goal: 2,
    start: START,
    events: [{ session: '2026-11-17T18:00:00Z' }, { rollAt: '2026-11-23T12:00:00Z' }, { session: '2026-11-19T18:00:00Z' }],
    expected: { streakWeeks: 0, longestStreak: 0, passWeeks: 0, weekKey: '2026-W48', weekCount: 0 },
  },
  {
    name: 'a session in a later week rolls the state forward without rollWeek',
    timezone: 'UTC',
    goal: 3,
    start: START,
    events: [...week(W47, 3), { session: '2026-11-24T18:00:00Z' }],
    expected: { streakWeeks: 1, longestStreak: 1, passWeeks: 0, weekKey: '2026-W48', weekCount: 1 },
  },
  {
    name: 'the streak runs across the year end through ISO week 53',
    timezone: 'UTC',
    goal: 2,
    start: '2026-12-21T08:00:00Z',
    events: weeks('2026-12-21', 3, 2),
    expected: { streakWeeks: 3, longestStreak: 3, passWeeks: 0, weekKey: '2027-W01' },
  },
  {
    name: 'a pass earned on the fourth hit protects the very next week',
    timezone: 'Europe/Berlin',
    goal: 2,
    start: START,
    events: [...weeks(W47, 4, 2), { rollAt: '2026-12-15T12:00:00Z' }, ...week('2026-12-21', 2)],
    expected: { streakWeeks: 5, longestStreak: 5, passWeeks: 0, weekKey: '2026-W52' },
  },
];

describe('streak scenarios', () => {
  it('has at least 12 cases', () => {
    expect(scenarios.length).toBeGreaterThanOrEqual(12);
  });

  it.each(scenarios.map((s) => [s.name, s] as const))('%s', (_name, s) => {
    const { state } = simulate(s);
    const v = view(state);
    expect({ streakWeeks: v.streakWeeks, longestStreak: v.longestStreak, passWeeks: v.passWeeks }).toEqual({
      streakWeeks: s.expected.streakWeeks,
      longestStreak: s.expected.longestStreak,
      passWeeks: s.expected.passWeeks,
    });
    if (s.expected.weekKey) expect(state.weekKey).toBe(s.expected.weekKey);
    if (s.expected.weekCount !== undefined) expect(state.weekCount).toBe(s.expected.weekCount);
  });
});
