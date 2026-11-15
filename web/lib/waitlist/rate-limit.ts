// Fixed-size sliding window per key (the client IP).
// In memory, so the limit holds per server instance. On a serverless host each
// warm instance keeps its own window; that is enough to stop one client
// hammering the form, and Firestore writes are idempotent per email anyway.

export interface RateLimiter {
  /** Records one hit for `key` at `now` (ms). Returns false if the hit is over the limit. */
  hit(key: string, now: number): boolean
  /** Seconds until `key` may try again (0 if it may now). */
  retryAfter(key: string, now: number): number
}

export function createMemoryRateLimiter(opts: { limit: number; windowMs: number; maxKeys?: number }): RateLimiter {
  const { limit, windowMs } = opts
  const maxKeys = opts.maxKeys ?? 10_000
  const hits = new Map<string, number[]>()

  function recent(key: string, now: number): number[] {
    const list = (hits.get(key) ?? []).filter((t) => now - t < windowMs)
    if (list.length) hits.set(key, list)
    else hits.delete(key)
    return list
  }

  function prune(now: number) {
    if (hits.size <= maxKeys) return
    for (const key of hits.keys()) {
      recent(key, now)
      if (hits.size <= maxKeys) return
    }
    // Still full of active keys: drop the oldest entries (Map keeps insertion order).
    for (const key of hits.keys()) {
      hits.delete(key)
      if (hits.size <= maxKeys) return
    }
  }

  return {
    hit(key, now) {
      const list = recent(key, now)
      if (list.length >= limit) return false
      list.push(now)
      hits.set(key, list)
      prune(now)
      return true
    },
    retryAfter(key, now) {
      const list = recent(key, now)
      if (list.length < limit) return 0
      return Math.max(1, Math.ceil((list[0] + windowMs - now) / 1000))
    },
  }
}

/**
 * The client IP. On Vercel the platform sets x-forwarded-for itself, so its first
 * entry is the real client. Behind another proxy, make sure it overwrites the header.
 */
export function clientIp(headers: Headers): string {
  const forwarded = headers.get('x-forwarded-for')
  if (forwarded) {
    const first = forwarded.split(',')[0]?.trim()
    if (first) return first
  }
  const real = headers.get('x-real-ip')?.trim()
  return real || 'unknown'
}
