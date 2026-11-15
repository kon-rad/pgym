import type { Metadata } from 'next'
import Link from 'next/link'
import type { ReactNode } from 'react'
import { PageHead, SupportEmail } from '@/components/PageHead'
import { site } from '@/lib/site'

export const metadata: Metadata = {
  title: 'Support',
  description: 'Help with PGYM: contact, and answers to the common questions.',
  alternates: { canonical: '/support' },
}

// Answers use the app's own screen and button names from pgym-app-copy.md.

const QUESTIONS: { q: string; a: ReactNode }[] = [
  {
    q: 'How do I start a session?',
    a: (
      <p>
        On Today, tap Start session. Your next routine opens with last session&apos;s weights already filled in. Tap
        the check on each set; change the weight or reps only when they change.
      </p>
    ),
  },
  {
    q: 'Why can I not pick a photo from my library?',
    a: (
      <p>
        The proof photo comes from the camera inside PGYM only. That is what makes the card proof: the photo was
        taken in the session, and the time and number are set by our server, not the phone.
      </p>
    ),
  },
  {
    q: 'The time on my card is not the time on my phone.',
    a: (
      <p>
        The card shows the time our server received the photo, in your time zone. If you were offline, the card
        shows a pending stamp until it syncs, then the server time replaces it. A session started before midnight
        counts for the day it started.
      </p>
    ),
  },
  {
    q: 'How does the streak count?',
    a: (
      <p>
        In weeks. Hit your weekly goal and the streak moves. Rest days never break it. Every four weeks you hit earns
        a pass week, used for you automatically. A session counts once it has at least one logged set and a proof
        photo.
      </p>
    ),
  },
  {
    q: 'How do I turn the physique score on or off?',
    a: (
      <p>
        Profile, then Privacy and data, then Physique score. It needs you to be 18 or older. Turning it off deletes
        every stored score and tip; your photos and proofs stay.
      </p>
    ),
  },
  {
    q: 'Why is there no score for one session?',
    a: (
      <p>
        The analysis skips photos it cannot read fairly: no person in frame, more than one person, face only, too
        dark, or anyone who looks under 18. The session still counts.
      </p>
    ),
  },
  {
    q: 'How do I give my AI agent access, or take it back?',
    a: (
      <p>
        Profile, then Agent access. Make a token, choose what it can read, and paste it into your agent. Revoke it on
        the same screen; it stops working at once.
      </p>
    ),
  },
  {
    q: 'How do I delete my account?',
    a: (
      <p>
        In the app: Profile, then Privacy and data, then Delete account. Without the app, see{' '}
        <Link href="/delete-account">Delete your account</Link>.
      </p>
    ),
  },
]

export default function SupportPage() {
  return (
    <div className="page">
      <div className="wrap">
        <PageHead label="Support" title="Support">
          <p className="lede">
            Write to <SupportEmail subject="PGYM support" />. A person reads every message.
          </p>
        </PageHead>
        <div className="faq">
          {QUESTIONS.map((item) => (
            <details key={item.q}>
              <summary>{item.q}</summary>
              <div>{item.a}</div>
            </details>
          ))}
        </div>
        <div className="prose" style={{ marginTop: 40 }}>
          <h2>Found a bug?</h2>
          <p>
            PGYM is open source. You can report a bug on <a href={`${site.githubUrl}/issues`}>GitHub</a>. For a
            security problem, please do not open a public issue; use{' '}
            <a href={`${site.githubUrl}/security/advisories/new`}>private reporting on GitHub</a> or email{' '}
            <SupportEmail subject="Security" />.
          </p>
        </div>
      </div>
    </div>
  )
}
