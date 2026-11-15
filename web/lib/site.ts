// Site settings, all from the environment. Nothing account-specific is committed:
// see "Environment" in web/README.md for every variable.

function clean(value: string | undefined): string {
  return (value ?? '').trim()
}

const appStoreUrl = clean(process.env.NEXT_PUBLIC_APP_STORE_URL)

export const site = {
  name: 'PGYM',
  line: 'Proof of gym.',
  /** Meta title and description, from pgym-landing-copy.md ("Meta title", "Meta description"). */
  title: 'PGYM: Proof of gym for your iPhone',
  description:
    'Log your sets, take one photo, and get a card stamped with the time and your proof number. You pick the days a week. Rest days never break it.',
  url: clean(process.env.NEXT_PUBLIC_SITE_URL) || 'http://localhost:3000',
  supportEmail: clean(process.env.NEXT_PUBLIC_SUPPORT_EMAIL),
  /** Legal name in the footer and the legal pages. Undecided, so it stays the [COMPANY] placeholder. */
  operator: clean(process.env.NEXT_PUBLIC_OPERATOR_NAME) || '[COMPANY]',
  /** Postal address for the support page and the legal pages. Undecided: [ADDRESS]. */
  address: clean(process.env.NEXT_PUBLIC_OPERATOR_ADDRESS) || '[ADDRESS]',
  githubUrl: 'https://github.com/kon-rad/pgym',
  /** The agent API host, shown in the example request. Placeholder until chosen. */
  apiUrl: clean(process.env.NEXT_PUBLIC_API_URL).replace(/\/+$/, '') || 'https://[API-DOMAIN]',
  appStoreUrl,
  /**
   * The one launch flag. Off: every call to action is the waitlist form.
   * On (and an App Store URL set): every call to action is the App Store badge.
   */
  appLive: clean(process.env.NEXT_PUBLIC_APP_LIVE) === 'true' && appStoreUrl !== '',
} as const

/** The host to print in copy: the configured domain, or the [DOMAIN] placeholder. */
export function displayHost(): string {
  if (!process.env.NEXT_PUBLIC_SITE_URL) return '[DOMAIN]'
  try {
    const u = new URL(site.url)
    return u.hostname === 'localhost' || u.hostname === '127.0.0.1' ? '[DOMAIN]' : u.host
  } catch {
    return '[DOMAIN]'
  }
}

export function mailto(subject?: string): string | null {
  if (!site.supportEmail) return null
  return `mailto:${site.supportEmail}${subject ? `?subject=${encodeURIComponent(subject)}` : ''}`
}
