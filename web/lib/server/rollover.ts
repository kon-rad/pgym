import { rollWeek } from './domain/handlers';
import { services } from './firebase';
import { log } from './log';

let lastStarted = 0;
let current: Promise<void> | undefined;

/** Replaces the former scheduler: active traffic closes any due weeks at most once a minute. */
export function triggerLazyWeekRollover(now = Date.now()): Promise<void> {
  if (current) return current;
  if (now - lastStarted < 60_000) return Promise.resolve();
  lastStarted = now;
  current = rollWeek(services())
    .then(() => undefined)
    .catch((error) => log.warn('rollWeek.failed', { error: String(error) }))
    .finally(() => { current = undefined; });
  return current;
}
