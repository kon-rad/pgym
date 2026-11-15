import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { POST } from '@/app/api/waitlist/route'
import { setWaitlistDeps } from '@/lib/waitlist/deps'
import { createMemoryRateLimiter } from '@/lib/waitlist/rate-limit'
import { createMemoryWaitlistStore, type MemoryWaitlistStore } from '@/lib/waitlist/store'
import { normalizeEmail } from '@/lib/waitlist/validate'

// The Firestore store is never touched here: every test injects the in-memory store.
// If one did reach Firestore, this mock makes it fail loudly.
vi.mock('@/lib/waitlist/firestore-store', () => ({
  createFirestoreWaitlistStore: () => ({
    add: async () => {
      throw new Error('Firestore must not be called from tests')
    },
  }),
}))

let store: MemoryWaitlistStore
let clock: number

function post(body: unknown, ip = '203.0.113.7', contentType = 'application/json') {
  return POST(
    new Request('http://localhost/api/waitlist', {
      method: 'POST',
      headers: { 'content-type': contentType, 'x-forwarded-for': ip },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    }),
  )
}

beforeEach(() => {
  store = createMemoryWaitlistStore()
  clock = 1_700_000_000_000
  setWaitlistDeps({
    store,
    limiter: createMemoryRateLimiter({ limit: 5, windowMs: 60_000 }),
    now: () => clock,
    log: () => {},
  })
})

afterEach(() => setWaitlistDeps(null))

describe('POST /api/waitlist', () => {
  it('stores a valid email once, even when it is sent twice', async () => {
    const first = await post({ email: 'Lifter@Example.com', source: 'hero' })
    expect(first.status).toBe(200)
    expect(await first.json()).toMatchObject({ ok: true, status: 'joined' })

    const second = await post({ email: '  lifter@example.com ', source: 'final-call' })
    expect(second.status).toBe(200)
    expect(await second.json()).toMatchObject({ ok: true, status: 'joined' })

    expect(store.entries.size).toBe(1)
    const entry = store.entries.get('lifter@example.com')
    expect(entry).toMatchObject({ email: 'lifter@example.com', source: 'hero' })
    expect(entry?.createdAt).toBeInstanceOf(Date)
  })

  it('rejects an invalid email and stores nothing', async () => {
    for (const email of ['not-an-email', 'a@b', 'a b@example.com', '@example.com', 'x@example.c', '', 42]) {
      const res = await post({ email }, `198.51.100.${String(email).length}`)
      expect(res.status, `email ${JSON.stringify(email)}`).toBe(400)
      expect(await res.json()).toMatchObject({ ok: false, status: 'invalid' })
    }
    expect(store.entries.size).toBe(0)
  })

  it('rejects a body that is not JSON', async () => {
    const res = await post('{nope')
    expect(res.status).toBe(400)
    expect(store.entries.size).toBe(0)
  })

  it('rejects the sixth request in a minute from one IP, then lets it in after the window', async () => {
    for (let i = 1; i <= 5; i++) {
      const res = await post({ email: `lifter${i}@example.com` })
      expect(res.status, `request ${i}`).toBe(200)
    }
    const sixth = await post({ email: 'lifter6@example.com' })
    expect(sixth.status).toBe(429)
    expect(sixth.headers.get('retry-after')).toBe('60')
    expect(await sixth.json()).toMatchObject({ ok: false, status: 'limited' })
    expect(store.entries.has('lifter6@example.com')).toBe(false)

    // Another IP is not affected.
    expect((await post({ email: 'other@example.com' }, '192.0.2.1')).status).toBe(200)

    // A minute later the first IP may try again.
    clock += 60_000
    expect((await post({ email: 'lifter6@example.com' })).status).toBe(200)
    expect(store.entries.size).toBe(7)
  })

  it('counts invalid requests toward the limit too', async () => {
    for (let i = 0; i < 5; i++) expect((await post({ email: 'bad' })).status).toBe(400)
    expect((await post({ email: 'good@example.com' })).status).toBe(429)
  })

  it('uses the first x-forwarded-for entry as the client IP', async () => {
    for (let i = 0; i < 5; i++) await post({ email: `a${i}@example.com` }, '203.0.113.9, 10.0.0.1')
    expect((await post({ email: 'b@example.com' }, '203.0.113.9, 10.0.0.2')).status).toBe(429)
  })

  it('accepts a no-JavaScript form post and redirects back to the page', async () => {
    const res = await post('email=form%40example.com&source=hero', '203.0.113.20', 'application/x-www-form-urlencoded')
    expect(res.status).toBe(303)
    expect(res.headers.get('location')).toBe('/?waitlist=joined#join')
    expect(store.entries.has('form@example.com')).toBe(true)

    const bad = await post('email=nope', '203.0.113.20', 'application/x-www-form-urlencoded')
    expect(bad.status).toBe(303)
    expect(bad.headers.get('location')).toBe('/?waitlist=invalid#join')
  })

  it('answers success to a filled honeypot without storing', async () => {
    const res = await post({ email: 'bot@example.com', company: 'Bots Inc' })
    expect(res.status).toBe(200)
    expect(store.entries.size).toBe(0)
  })

  it('returns 503 when the store fails', async () => {
    setWaitlistDeps({
      store: { add: async () => Promise.reject(new Error('down')) },
      limiter: createMemoryRateLimiter({ limit: 5, windowMs: 60_000 }),
      now: () => clock,
      log: () => {},
    })
    const res = await post({ email: 'lifter@example.com' })
    expect(res.status).toBe(503)
    expect(await res.json()).toMatchObject({ ok: false, status: 'unavailable' })
  })
})

describe('normalizeEmail', () => {
  it('lower-cases and trims', () => {
    expect(normalizeEmail('  A.B+gym@Example.CO.uk ')).toBe('a.b+gym@example.co.uk')
  })
  it('rejects over-long addresses', () => {
    expect(normalizeEmail(`${'a'.repeat(65)}@example.com`)).toBeNull()
    expect(normalizeEmail(`a@${'b'.repeat(250)}.com`)).toBeNull()
  })
})
