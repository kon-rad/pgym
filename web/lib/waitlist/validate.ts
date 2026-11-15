// Email and source validation for the waitlist route.
// Deliberately simple: one @, a dot in the domain, no spaces, RFC length limits.
// The real check is the confirmation email at launch, not this regex.

const EMAIL_RE = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/
const MAX_EMAIL = 254
const MAX_LOCAL = 64

export function normalizeEmail(input: unknown): string | null {
  if (typeof input !== 'string') return null
  const email = input.trim().toLowerCase()
  if (email.length === 0 || email.length > MAX_EMAIL) return null
  if (!EMAIL_RE.test(email)) return null
  const local = email.slice(0, email.lastIndexOf('@'))
  if (local.length > MAX_LOCAL) return null
  const tld = email.slice(email.lastIndexOf('.') + 1)
  if (tld.length < 2) return null
  return email
}

const SOURCE_RE = /^[a-z0-9_-]{1,40}$/

/** Where the signup came from ("hero", "final-call"). Anything odd becomes "site". */
export function normalizeSource(input: unknown): string {
  if (typeof input !== 'string') return 'site'
  const source = input.trim().toLowerCase()
  return SOURCE_RE.test(source) ? source : 'site'
}
