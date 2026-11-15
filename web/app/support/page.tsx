import type { Metadata } from 'next'
import Link from 'next/link'
import type { ReactNode } from 'react'
import { SupportEmail } from '@/components/PageHead'
import { displayHost, mailto, site } from '@/lib/site'

export const metadata: Metadata = {
  title: 'Support',
  description: 'Help with PGYM: contact, and answers to the common questions.',
  alternates: { canonical: '/support' },
}

// Copy: pgym-landing-copy.md, "Support page (/support)", word for word.
// [PLACEHOLDER: domain] prints as [DOMAIN] until NEXT_PUBLIC_SITE_URL is set;
// the support email, company name and postal address likewise.

function SiteUrl({ path }: { path: string }) {
  return <Link href={path}>{`https://${displayHost()}${path}`}</Link>
}

const SUPPORT_QUESTIONS: { q: string; a: ReactNode }[] = [
  {
    q: 'I cannot sign in.',
    a: 'Check you are using the same method you signed up with: Apple, Google or email. If you used email, tap Forgot password on the sign-in screen and we send a reset link.',
  },
  {
    q: 'My proof says pending.',
    a: 'The card was made without a connection. It is stamped with the server time and your proof number as soon as your phone is back online. Keep the app open for a moment once you have signal.',
  },
  {
    q: 'How do I delete a session?',
    a: 'Open Progress, tap the card, then Delete. The photo and the card are removed, and your counts are recalculated.',
  },
  {
    q: 'How do I turn off the physique score?',
    a: 'Profile, then Privacy and data, then turn off Physique analysis. Every stored score is deleted.',
  },
  {
    q: 'I am not getting reminders.',
    a: 'Check that notifications for PGYM are on in iOS Settings. PGYM sends one reminder on each gym day you picked, at your time, and none once the session is logged. After 5 reminders in a row go unopened it drops to one a week.',
  },
  {
    q: 'How do I get a copy of my data?',
    a: 'Profile, then Privacy and data, then Export my data.',
  },
  {
    q: 'How do I delete my account?',
    a: (
      <>
        Profile, then Privacy and data, then Delete account. It removes your photos, cards, sessions and sign-in. If you
        no longer have the app, use the form at <SiteUrl path="/delete-account" />
      </>
    ),
  },
]

export default function SupportPage() {
  const mail = mailto('PGYM support')
  return (
    <div className="doc">
      <div className="wrap support-grid">
        <header className="support-contact">
          <h1 className="doc-title">Support</h1>
          <p>
            Email <SupportEmail subject="PGYM support" /> and we will get back to you. If something is not working, tell
            us which iPhone and iOS version you have, and what you tapped before it happened.
          </p>
          {mail ? (
            <a className="btn btn-secondary btn-block" href={mail}>
              {site.supportEmail}
            </a>
          ) : null}
        </header>

        <div className="support-questions">
          <h2 className="doc-h2">Common questions</h2>
          <div className="faq">
            {SUPPORT_QUESTIONS.map((item) => (
              <details key={item.q}>
                <summary>{item.q}</summary>
                <p>{item.a}</p>
              </details>
            ))}
          </div>

          <div className="prose support-foot">
            <p>
              Found a security problem? Do not send the details by plain email. See <SiteUrl path="/open-source" /> for
              how to report it privately.
            </p>
            <p>
              PGYM is made by {site.operator}, {site.address}.
            </p>
            <p>
              Privacy policy: <SiteUrl path="/privacy" />
              <br />
              Terms of use: <SiteUrl path="/terms" />
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
