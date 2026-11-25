/**
 * Session totals and per-exercise bests. Pure. The server recomputes these at
 * stamp time from the logged sets, so the numbers on the card and in the agent
 * API do not depend on what the phone claimed.
 */

export interface LoggedSet {
  n?: number;
  weight?: number; // kilograms
  reps?: number;
  type?: string; // working, warmup, drop, failure
  done?: boolean;
  rpe?: number;
}

export interface LoggedExercise {
  exerciseId: string;
  name?: string;
  sets?: LoggedSet[];
}

export interface BestSet {
  weight: number;
  reps: number;
}

export interface ExerciseStats {
  bestWeight: number;
  bestSet: BestSet | null;
  bestE1rm: number;
  lastPerformedAt: Date | null;
  sessionCount: number;
}

export interface SessionTotals {
  setCount: number;
  totalVolume: number;
  perExercise: Map<string, { bestWeight: number; bestSet: BestSet | null; bestE1rm: number }>;
}

const MAX_EXERCISES = 100;
const MAX_SETS = 100;
const MAX_WEIGHT_KG = 1000;
const MAX_REPS = 1000;

function finiteInRange(v: unknown, max: number): number {
  return typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= max ? v : 0;
}

/** Epley estimate of the one-rep max, rounded to 0.1 kg. */
export function e1rm(weight: number, reps: number): number {
  if (weight <= 0 || reps <= 0) return 0;
  const est = reps === 1 ? weight : weight * (1 + reps / 30);
  return Math.round(est * 10) / 10;
}

/** A set counts when it is done and is not a warm-up. */
function counts(set: LoggedSet): boolean {
  return set.done === true && set.type !== 'warmup';
}

export function sanitizeExercises(raw: unknown): LoggedExercise[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .slice(0, MAX_EXERCISES)
    .filter((e): e is LoggedExercise => !!e && typeof e === 'object' && typeof (e as LoggedExercise).exerciseId === 'string')
    .filter((e) => /^[A-Za-z0-9_-]{1,128}$/.test(e.exerciseId))
    .map((e) => ({ ...e, sets: Array.isArray(e.sets) ? e.sets.slice(0, MAX_SETS) : [] }));
}

export function sessionTotals(exercises: LoggedExercise[]): SessionTotals {
  let setCount = 0;
  let totalVolume = 0;
  const perExercise: SessionTotals['perExercise'] = new Map();
  for (const ex of exercises) {
    const best = perExercise.get(ex.exerciseId) ?? { bestWeight: 0, bestSet: null, bestE1rm: 0 };
    for (const set of ex.sets ?? []) {
      if (!counts(set)) continue;
      const weight = finiteInRange(set.weight, MAX_WEIGHT_KG);
      const reps = Math.floor(finiteInRange(set.reps, MAX_REPS));
      setCount += 1;
      totalVolume += weight * reps;
      if (weight > best.bestWeight) best.bestWeight = weight;
      const est = e1rm(weight, reps);
      if (est > best.bestE1rm) {
        best.bestE1rm = est;
        best.bestSet = { weight, reps };
      }
    }
    perExercise.set(ex.exerciseId, best);
  }
  return { setCount, totalVolume: Math.round(totalVolume * 10) / 10, perExercise };
}

export function emptyStats(): ExerciseStats {
  return { bestWeight: 0, bestSet: null, bestE1rm: 0, lastPerformedAt: null, sessionCount: 0 };
}

/** Merge one session into an exercise's stats. `isNewBest` when weight or e1RM went up. */
export function mergeStats(
  prior: ExerciseStats,
  session: { bestWeight: number; bestSet: BestSet | null; bestE1rm: number },
  performedAt: Date,
): { stats: ExerciseStats; isNewBest: boolean } {
  const isNewBest =
    prior.sessionCount > 0 && (session.bestWeight > prior.bestWeight || session.bestE1rm > prior.bestE1rm);
  const betterSet = session.bestE1rm > prior.bestE1rm;
  return {
    isNewBest,
    stats: {
      bestWeight: Math.max(prior.bestWeight, session.bestWeight),
      bestSet: betterSet ? session.bestSet : prior.bestSet,
      bestE1rm: Math.max(prior.bestE1rm, session.bestE1rm),
      lastPerformedAt:
        prior.lastPerformedAt && prior.lastPerformedAt > performedAt ? prior.lastPerformedAt : performedAt,
      sessionCount: prior.sessionCount + 1,
    },
  };
}
