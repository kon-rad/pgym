import { createFirestoreWaitlistStore } from './firestore-store'
import { WAITLIST_LIMIT, WAITLIST_WINDOW_MS, type WaitlistDeps } from './handler'
import { createMemoryRateLimiter } from './rate-limit'

// One set of dependencies per server instance. Tests swap them with setWaitlistDeps.

let deps: WaitlistDeps | null = null

function defaults(): WaitlistDeps {
  return {
    store: createFirestoreWaitlistStore(),
    limiter: createMemoryRateLimiter({ limit: WAITLIST_LIMIT, windowMs: WAITLIST_WINDOW_MS }),
    now: () => Date.now(),
    log: (message, err) => console.error(`[waitlist] ${message}:`, err instanceof Error ? err.message : err),
  }
}

export function getWaitlistDeps(): WaitlistDeps {
  deps ??= defaults()
  return deps
}

/** Test hook: replace some or all dependencies. Pass null to reset to the defaults. */
export function setWaitlistDeps(next: Partial<WaitlistDeps> | null): void {
  deps = next ? { ...defaults(), ...next } : null
}
