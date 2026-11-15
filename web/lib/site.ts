// Site settings, all from the environment. Nothing account-specific is committed:
// see web/.env.example for every variable.

function clean(value: string | undefined): string {
  return (value ?? '').trim()
}

const appStoreUrl = clean(process.env.NEXT_PUBLIC_APP_STORE_URL)

export const site = {
  name: 'PGYM',
  line: 'Proof of gym.',
  description:
    'Log your sets, take one photo in the gym, get a timestamped proof card with a number that only goes up. An iPhone app.',
  url: clean(process.env.NEXT_PUBLIC_SITE_URL) || 'http://localhost:3000',
  supportEmail: clean(process.env.NEXT_PUBLIC_SUPPORT_EMAIL),
  /** Legal name shown in the footer and the legal pages. Undecided, so it defaults to the product name. */
  operator: clean(process.env.NEXT_PUBLIC_OPERATOR_NAME) || 'PGYM',
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

export function mailto(subject?: string): string | null {
  if (!site.supportEmail) return null
  return `mailto:${site.supportEmail}${subject ? `?subject=${encodeURIComponent(subject)}` : ''}`
}
