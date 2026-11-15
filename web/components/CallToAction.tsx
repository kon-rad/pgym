import Link from 'next/link'
import { site } from '@/lib/site'
import { WaitlistForm } from './WaitlistForm'

// The one launch flag (NEXT_PUBLIC_APP_LIVE, see lib/site.ts) decides what every
// call to action on the site is: the waitlist form before launch, the App Store
// badge after.

function AppleGlyph() {
  return (
    <svg width="22" height="26" viewBox="0 0 17 20" aria-hidden="true" fill="currentColor">
      <path d="M14.1 10.6c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8C4.2 5.1 2.6 6.1 1.8 7.6c-1.8 3.1-.5 7.6 1.3 10.1.8 1.2 1.8 2.6 3.1 2.5 1.3-.1 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.7-1-2.8-4.4ZM11.7 3.5c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4Z" />
    </svg>
  )
}

/**
 * A badge drawn in the App Store badge layout. Swap for Apple's official badge
 * artwork (from the Apple marketing resources site) before launch; see web/README.md.
 */
export function AppStoreBadge() {
  return (
    <a className="store-badge" href={site.appStoreUrl} aria-label="Download PGYM on the App Store">
      <AppleGlyph />
      <span>
        <small>Download on the</small>
        <strong>App Store</strong>
      </span>
    </a>
  )
}

export function CallToAction({ source, readQuery }: { source: string; readQuery?: boolean }) {
  if (site.appLive) return <AppStoreBadge />
  return <WaitlistForm source={source} readQuery={readQuery} />
}

/** The small button in the header. */
export function HeaderAction() {
  if (site.appLive) {
    return (
      <a className="btn btn-primary btn-small" href={site.appStoreUrl}>
        Get the app
      </a>
    )
  }
  return (
    <Link className="btn btn-primary btn-small" href="/#join">
      Join the waitlist
    </Link>
  )
}
