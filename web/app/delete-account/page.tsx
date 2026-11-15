import type { Metadata } from 'next'
import Link from 'next/link'
import { SupportEmail } from '@/components/PageHead'

export const metadata: Metadata = {
  title: 'Delete your account',
  description: 'How to delete your PGYM account and everything in it, with or without the app.',
  alternates: { canonical: '/delete-account' },
}

// Layout: pgym-landing-design.md 5, "/delete-account": the H1, then two blocks,
// "In the app" (the taps, with mono step numbers) and "No longer have the app",
// stacked on a phone and side by side from 768 px. What is deleted comes from
// view F7 in pgym-app-copy.md, so the site and the app say the same thing.
//
// The design's deletion request form is not built: how a request is confirmed
// is an open question (design open question 7), so this page asks for an email
// from the sign-up address instead.

export default function DeleteAccountPage() {
  return (
    <div className="doc">
      <div className="wrap">
        <header className="doc-head doc-head-wide">
          <h1 className="doc-title">Delete your account</h1>
          <p className="lede doc-lede">You can delete your account and everything in it at any time.</p>
        </header>
        <div className="delete-grid">
          <section className="delete-block prose" aria-labelledby="in-app">
            <h2 id="in-app">In the app</h2>
            <ol className="steps-list">
              <li>Open PGYM and go to Profile.</li>
              <li>Tap Privacy and data, then Delete account.</li>
              <li>Sign in again if asked. It keeps someone else from doing this.</li>
              <li>Type DELETE to confirm, then tap Delete my account.</li>
            </ol>
            <h2>What is deleted</h2>
            <ul>
              <li>Every photo and card</li>
              <li>Every session, set and routine</li>
              <li>Your scores and tips</li>
              <li>Your agent tokens</li>
              <li>Your sign-in</li>
            </ul>
            <p>
              If you signed in with Apple, PGYM&apos;s access to your Apple ID is removed too. Cards you already
              shared stay wherever you posted them. PGYM cannot remove those.
            </p>
          </section>
          <section className="delete-block prose" aria-labelledby="no-app">
            <h2 id="no-app">No longer have the app</h2>
            <p>
              Email <SupportEmail subject="Delete my PGYM account" /> from the address you signed up with, with the
              subject &ldquo;Delete my PGYM account&rdquo;. We reply to confirm it is you, then delete the account and
              tell you when it is done. We never ask for your password.
            </p>
            <h2>Only want to remove photos or scores?</h2>
            <p>
              You do not have to delete the account. In Profile, then Privacy and data, you can delete all photos, or
              turn off the physique score, which deletes every stored score and tip. See the{' '}
              <Link href="/privacy">privacy policy</Link> for what is kept and for how long.
            </p>
          </section>
        </div>
      </div>
    </div>
  )
}
