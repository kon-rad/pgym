import Link from 'next/link'
import type { ReactNode } from 'react'
import { EditorScreen, Phone, ProgressScreen, ProofWallScreen } from '@/components/AppScreens'
import { CallToAction, HERO_EMAIL_ID } from '@/components/CallToAction'
import { LoopDemo } from '@/components/LoopDemo'
import { ProofCard, type ProofCardProps } from '@/components/ProofCard'
import { StreakWeek } from '@/components/StreakWeek'
import { site } from '@/lib/site'

// Home. Sections and layout: pgym-landing-design.md section 2, in the order of
// pgym-landing-pages.md. Copy: pgym-landing-copy.md, word for word; display lines
// are written in sentence case there and set in upper case by the CSS. Every
// number on a card or a screen is an example on the demo account; there are no
// user counts, ratings or testimonials, and the physique score is never shown.

const HERO_CARD: ProofCardProps = {
  // The sample session from the proof-card template (pgym-card-4x5.svg).
  proof: 42,
  streakWeeks: 7,
  time: 'SUN 15 NOV 2026 · 18:47',
  name: 'Push A: Chest, Shoulders, Triceps',
  sets: 18,
  total: '6,240',
  duration: '1:12',
  filter: 'iron',
  scene: 0,
}

const DEMO_CARD: ProofCardProps = { ...HERO_CARD, proof: 43, time: 'TUE 17 NOV 2026 · 07:02' }

// Eight cards, two in each filter, in the order Iron, Chalk, Plate, Raw twice,
// so each column of the 4 x 2 grid is one filter (pgym-landing-design.md 2.4).
const FILTER_NAME = { iron: 'Iron', chalk: 'Chalk', plate: 'Plate', raw: 'Raw' } as const
const EXAMPLE_CARDS: ProofCardProps[] = [
  { proof: 1, streakWeeks: 0, time: 'MON 28 SEP 2026 · 07:10', name: 'Full body', sets: 12, total: '2,880', duration: '0:44', filter: 'iron', scene: 1 },
  { proof: 9, streakWeeks: 2, time: 'WED 07 OCT 2026 · 18:22', name: 'Legs', sets: 15, total: '5,410', duration: '0:52', filter: 'chalk', scene: 0 },
  { proof: 17, streakWeeks: 4, time: 'FRI 23 OCT 2026 · 12:05', name: 'Upper', sets: 20, total: '4,410', duration: '1:01', filter: 'plate', scene: 2 },
  { proof: 25, streakWeeks: 5, time: 'SAT 31 OCT 2026 · 10:14', name: 'Pull A', sets: 16, total: '3,940', duration: '0:48', filter: 'raw', scene: 3 },
  { proof: 33, streakWeeks: 6, time: 'MON 09 NOV 2026 · 07:12', name: 'Push B', sets: 16, total: '4,480', duration: '0:46', filter: 'iron', scene: 2 },
  { proof: 38, streakWeeks: 6, time: 'WED 11 NOV 2026 · 18:30', name: 'Legs', sets: 15, total: '6,105', duration: '0:55', filter: 'chalk', scene: 1 },
  { proof: 41, streakWeeks: 6, time: 'FRI 13 NOV 2026 · 19:20', name: 'Pull B', sets: 17, total: '4,060', duration: '0:50', filter: 'plate', scene: 3 },
  { proof: 42, streakWeeks: 7, time: 'SUN 15 NOV 2026 · 18:47', name: 'Push A', sets: 18, total: '6,240', duration: '1:12', filter: 'raw', scene: 0 },
]

// pgym-landing-copy.md, "The eight questions". The "Is it free?" answer says the
// price is not decided, which is the truth on 2026-11-15.
const FAQ: { q: string; a: ReactNode }[] = [
  {
    q: 'Is it free?',
    a: 'PGYM is not out yet, and the price is not decided. It will be on this page before launch, and people on the waitlist hear first.',
  },
  {
    q: 'Which phones does it work on?',
    a: 'iPhone only for now. There is no Android, iPad or Apple Watch version in the first release.',
  },
  {
    q: 'What happens to my photos?',
    a: 'They are stored privately and only you can open them, plus any agent you give photo access. Nothing is shared until you share a card. You can delete one session, every photo, or your whole account from inside the app, and deleting your account removes all of it.',
  },
  {
    q: 'How is the physique score made?',
    a: "It is optional and off until you turn it on. When it is on, the session photo is sent to Google's Gemini model, which returns a 0 to 100 estimate of visible muscle development and symmetry, plus one training tip. Only you see it, it is compared only with your own earlier scores, and it never goes on the card. It is an AI estimate from one photo, not medical advice, and it is not available under 18. Turn it off any time and every stored score is deleted.",
  },
  {
    q: 'What counts as a proof?',
    a: 'One logged set and one photo from the PGYM camera. The time and the proof number come from our server when the photo arrives, not from your phone. Photos from your camera roll cannot be used. A retake replaces the photo; it is still one proof.',
  },
  {
    q: 'What if I miss a week?',
    a: 'Nothing is lost by a rest day; the streak counts weeks, not days. Every 4 weeks you hit earns a pass week, used automatically on a week you fall short. A new week starts on Monday either way.',
  },
  {
    q: 'Does it work without signal?',
    a: 'Yes. Sets save on your phone as you log them, and the card is made on the phone. The proof is stamped with the server time when you are back online.',
  },
  {
    q: 'Can I see the code?',
    a: (
      <>
        Yes. PGYM is open source on GitHub. If you use an AI agent, you can give it a read-only token to read your
        sessions, streak and lifts. See the <Link href="/open-source">open source</Link> and{' '}
        <Link href="/agents">agents</Link> pages.
      </>
    ),
  },
]

function Chevron() {
  return (
    <svg className="chevron" width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
      <path d="M7 4l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export default function Home() {
  return (
    <>
      {/* 2. Hero */}
      <section className="hero" aria-labelledby="hero-title">
        <div className="wrap grid12">
          <div className="hero-copy" id="join">
            <h1 id="hero-title" className="display display-h1">
              Proof of <br />
              gym<span className="dot">.</span>
            </h1>
            <p className="lead">Log your sets. Take one photo. Get your proof.</p>
            <p className="hero-body">
              Every session ends in one card: your photo, the date and time, and a proof number set by our server. Rest
              days never break the streak.
            </p>
            <div className="hero-action">
              <CallToAction source="hero" readQuery inputId={HERO_EMAIL_ID} />
            </div>
            <p className="caption">{site.appLive ? 'iPhone only.' : 'iPhone only. Not out yet.'}</p>
          </div>
          <div className="hero-visual">
            <Phone
              size="m"
              desktop="l"
              className="hero-phone"
              label="The PGYM proof card editor: an example card in the Iron filter, stamped proof #042, 7 weeks running, Sunday 15 November 2026 at 18:47, Push A, 18 sets, 6,240 kg lifted, 1 hour 12 minutes."
            >
              <EditorScreen card={{ ...HERO_CARD, animateStamp: true }} />
            </Phone>
          </div>
        </div>
      </section>

      {/* 3. The loop */}
      <section className="section" aria-labelledby="loop-title">
        <div className="wrap">
          <h2 id="loop-title" className="display display-h2 section-title" data-reveal>
            How it works
          </h2>
          <LoopDemo card={DEMO_CARD} />
        </div>
      </section>

      {/* 4. The card */}
      <section className="section" aria-labelledby="card-title">
        <div className="wrap">
          <div className="section-head card-head" data-reveal>
            <span className="label">The card</span>
            <h2 id="card-title" className="display display-h2">
              Every session, numbered.
            </h2>
            <div className="card-lead">
              <p className="lead">
                Proof #001 is your first session. Proof #042 is the 42nd time you showed up. One layout, four filters,
                so your cards line up as a series.
              </p>
              <p className="label">Iron. Chalk. Plate. Raw.</p>
            </div>
          </div>
        </div>
        <div className="wrap wrap-bleed">
          <ul className="card-row" aria-label="Eight example proof cards, two in each filter">
            {EXAMPLE_CARDS.map((card, i) => (
              <li key={card.proof} data-reveal style={{ ['--i' as string]: i % 4 }}>
                <figure>
                  <ProofCard {...card} />
                  <figcaption className="label">{FILTER_NAME[card.filter ?? 'iron']}</figcaption>
                </figure>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* 5. The streak */}
      <section className="section" aria-labelledby="streak-title">
        <div className="wrap grid12 streak">
          <div className="streak-copy" data-reveal>
            <h2 id="streak-title" className="display display-h2">
              A streak that counts weeks.
            </h2>
            <p>You pick the number, from 2 to 6 days a week. Hit it and the week locks. Rest days never break the streak.</p>
            <p>Every 4 weeks you hit earns a pass week, used automatically, so one bad week does not erase months.</p>
          </div>
          <StreakWeek />
        </div>
      </section>

      {/* 6. Progress */}
      <section className="section" aria-labelledby="progress-title">
        <div className="wrap grid12 progress">
          <div className="progress-copy" data-reveal>
            <h2 id="progress-title" className="display display-h2">
              Watch it add up.
            </h2>
            <p className="lead">
              The proof wall puts every card in one grid, newest first. The last 12 weeks sit against your goal. Every
              lift keeps its best set and an estimated one-rep max.
            </p>
          </div>
          <div className="progress-frames" data-reveal>
            <Phone
              size="m"
              label="The Progress screen, example data: 42 proofs, a 7 week streak, sessions a week over 12 weeks against a goal of 4, the newest six cards, and best sets for bench press and back squat."
            >
              <ProgressScreen />
            </Phone>
            <Phone
              size="m"
              className="desktop-only"
              label="The proof wall, example data: every card in a grid, newest first, grouped by month, from proof #042 back to #025."
            >
              <ProofWallScreen />
            </Phone>
          </div>
        </div>
      </section>

      {/* 7. Private by default */}
      <section className="section" aria-labelledby="private-title">
        <div className="wrap">
          <h2 id="private-title" className="display display-h2 section-title" data-reveal>
            Private by default.
          </h2>
          <ul className="facts">
            <li className="fact" data-reveal>
              <span className="label">Photos</span>
              <p>
                Your photos are stored privately. Only you can open them, plus any agent you choose to give photo
                access. Nothing leaves the app until you share a card.
              </p>
            </li>
            <li className="fact" data-reveal>
              <span className="label">The score</span>
              <p>
                There is an optional AI physique score. It is off until you turn it on, only you see it, and it never
                goes on the card.
              </p>
            </li>
            <li className="fact" data-reveal>
              <span className="label">Your data</span>
              <p>
                You can delete a session, every photo, or <Link href="/delete-account">your whole account</Link> from
                inside the app.
              </p>
            </li>
          </ul>
          <p className="facts-link">
            <Link href="/privacy">Read the privacy policy</Link>
          </p>
        </div>
      </section>

      {/* 8. Questions */}
      <section className="section" aria-labelledby="faq-title">
        <div className="wrap grid12 questions">
          <h2 id="faq-title" className="display display-h2" data-reveal>
            Questions
          </h2>
          <div className="faq" data-reveal>
            {FAQ.map((item) => (
              <details key={item.q}>
                <summary>{item.q}</summary>
                <p>{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* 9. Final call */}
      <section className="section final-section" aria-labelledby="final-title">
        <div className="wrap final" data-reveal>
          <h2 id="final-title" className="display display-h2">
            Proof #001 is waiting<span className="dot">.</span>
          </h2>
          <div className="final-action">
            <CallToAction source="final-call" />
          </div>
        </div>
      </section>

      {/* 10. Built in the open */}
      <section className="section open-section" aria-labelledby="open-title">
        <div className="wrap">
          <h2 id="open-title" className="label open-label">
            Built in the open.
          </h2>
          <div className="open-grid">
            <Link className="open-card" href="/open-source" data-reveal>
              <span className="open-text">
                <strong>The code is on GitHub.</strong>
                <span>PGYM is open source. Read it, run it, or report a problem.</span>
                <span className="label">See the code</span>
              </span>
              <Chevron />
            </Link>
            <Link className="open-card" href="/agents" data-reveal>
              <span className="open-text">
                <strong>Your agent can read your training.</strong>
                <span>
                  Give your AI agent a read-only token and it can see your sessions, streak and lifts. It can plan next
                  week. It cannot make a proof.
                </span>
                <span className="label">For your agent</span>
              </span>
              <Chevron />
            </Link>
          </div>
        </div>
      </section>
    </>
  )
}
