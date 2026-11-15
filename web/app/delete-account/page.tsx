import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHead, SupportEmail } from '@/components/PageHead'

export const metadata: Metadata = {
  title: 'Delete your account',
  description: 'How to delete your PGYM account and everything in it, with or without the app.',
  alternates: { canonical: '/delete-account' },
}

// Strings for what is deleted come from view F7 in pgym-app-copy.md, so the site
// and the app say the same thing.

export default function DeleteAccountPage() {
  return (
    <div className="page">
      <div className="wrap">
        <PageHead label="Account" title="Delete your account">
          <p className="lede">You can delete your account and everything in it at any time.</p>
        </PageHead>
        <div className="prose">
          <h2>In the app</h2>
          <ol className="steps-list">
            <li>Open PGYM and go to Profile.</li>
            <li>Tap Privacy and data, then Delete account.</li>
            <li>Sign in again if asked. It keeps someone else from doing this.</li>
            <li>Type DELETE to confirm, then tap Delete my account.</li>
          </ol>

          <h2>Without the app</h2>
          <p>
            If you no longer have the app or your phone, email <SupportEmail subject="Delete my PGYM account" /> from
            the address you signed up with, with the subject &ldquo;Delete my PGYM account&rdquo;. We reply to confirm
            it is you, then delete the account and tell you when it is done. We never ask for your password.
          </p>

          <h2>What is deleted</h2>
          <ul>
            <li>Every photo and card</li>
            <li>Every session, set and routine</li>
            <li>Your scores and tips</li>
            <li>Your agent tokens</li>
            <li>Your sign-in</li>
          </ul>
          <p>
            If you signed in with Apple, PGYM&apos;s access to your Apple ID is removed too. Cards you already shared
            stay wherever you posted them. PGYM cannot remove those.
          </p>

          <h2>Only want to remove photos or scores?</h2>
          <p>
            You do not have to delete the account. In Profile, then Privacy and data, you can delete all photos, or
            turn off the physique score, which deletes every stored score and tip. See the{' '}
            <Link href="/privacy">privacy policy</Link> for what is kept and for how long.
          </p>
        </div>
      </div>
    </div>
  )
}
