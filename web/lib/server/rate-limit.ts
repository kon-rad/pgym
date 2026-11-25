import { HttpsError } from './errors';

const windows = new Map<string, { start: number; count: number }>();

export function enforceRateLimit(key: string, limit: number, windowMs: number, now = Date.now()) {
  const prior = windows.get(key);
  const current = !prior || now - prior.start >= windowMs ? { start: now, count: 0 } : prior;
  current.count += 1;
  windows.set(key, current);
  if (current.count > limit) throw new HttpsError('resource-exhausted', 'Too many requests. Try again shortly.');
}

export function resetRateLimits() {
  windows.clear();
}
