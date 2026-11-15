import { clientIp, type RateLimiter } from './rate-limit'
import type { WaitlistStore } from './store'
import { MESSAGES, type Outcome } from './messages'
import { normalizeEmail, normalizeSource } from './validate'

export interface WaitlistDeps {
  store: WaitlistStore
  limiter: RateLimiter
  now: () => number
  log?: (message: string, err?: unknown) => void
}

/** Five requests a minute per IP; the sixth is rejected. */
export const WAITLIST_LIMIT = 5
export const WAITLIST_WINDOW_MS = 60_000

export { MESSAGES }

const STATUS: Record<Outcome, number> = {
  joined: 200,
  invalid: 400,
  badRequest: 400,
  limited: 429,
  unavailable: 503,
}

const MAX_BODY = 4_096

function isForm(req: Request): boolean {
  const type = req.headers.get('content-type') ?? ''
  return type.startsWith('application/x-www-form-urlencoded') || type.startsWith('multipart/form-data')
}

async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  const length = Number(req.headers.get('content-length') ?? '0')
  if (length > MAX_BODY) return null
  try {
    if (isForm(req)) {
      const form = await req.formData()
      return Object.fromEntries([...form.entries()].map(([k, v]) => [k, typeof v === 'string' ? v : '']))
    }
    const text = await req.text()
    if (text.length > MAX_BODY) return null
    const json: unknown = JSON.parse(text)
    return json && typeof json === 'object' && !Array.isArray(json) ? (json as Record<string, unknown>) : null
  } catch {
    return null
  }
}

function respond(req: Request, outcome: Outcome, extraHeaders: Record<string, string> = {}): Response {
  // A plain HTML form post (no JavaScript) gets sent back to the page with the outcome.
  if (isForm(req)) {
    const back = new URL('/', req.url)
    back.searchParams.set('waitlist', outcome)
    back.hash = 'join'
    return new Response(null, { status: 303, headers: { Location: back.pathname + back.search + back.hash, ...extraHeaders } })
  }
  return Response.json(
    { ok: outcome === 'joined', status: outcome, message: MESSAGES[outcome] },
    { status: STATUS[outcome], headers: { 'Cache-Control': 'no-store', ...extraHeaders } },
  )
}

export async function handleWaitlist(req: Request, deps: WaitlistDeps): Promise<Response> {
  const now = deps.now()
  const ip = clientIp(req.headers)

  if (!deps.limiter.hit(ip, now)) {
    return respond(req, 'limited', { 'Retry-After': String(deps.limiter.retryAfter(ip, now)) })
  }

  const body = await readBody(req)
  if (!body) return respond(req, 'badRequest')

  // Honeypot: a hidden field people never fill. Bots that do get a success and no write.
  if (typeof body.company === 'string' && body.company.trim() !== '') return respond(req, 'joined')

  const email = normalizeEmail(body.email)
  if (!email) return respond(req, 'invalid')

  try {
    // 'exists' answers the same as 'created', so the form never says who is already on the list.
    await deps.store.add({ email, source: normalizeSource(body.source) })
    return respond(req, 'joined')
  } catch (err) {
    deps.log?.('waitlist write failed', err)
    return respond(req, 'unavailable')
  }
}
