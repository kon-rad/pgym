import Link from 'next/link'
import type { ReactNode } from 'react'
import { CallToAction } from '@/components/CallToAction'
import { LoopDemo } from '@/components/LoopDemo'
import { CardPhoto, ProofCard, type ProofCardProps, type Scene } from '@/components/ProofCard'
import { site } from '@/lib/site'

// Home. Sections in the order of pgym-landing-pages.md, "Home page sections".
// Copy follows the voice in pgym-design-style.md: short, flat, a little dry, no
// exclamation marks, no guilt. Every number on an example card is labelled as an
// example; there are no user counts, ratings or testimonials.

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

const BACK_CARD: ProofCardProps = {
  proof: 41,
  streakWeeks: 6,
  time: 'FRI 13 NOV 2026 · 12:05',
  name: 'Legs',
  sets: 15,
  total: '6,105',
  duration: '0:55',
  filter: 'plate',
  scene: 1,
}

const DEMO_CARD: ProofCardProps = { ...HERO_CARD, proof: 43 }

// Eight cards, two in each filter, so the series effect shows (section 4).
const EXAMPLE_CARDS: (ProofCardProps & { caption: string })[] = [
  { proof: 39, streakWeeks: 6, time: 'MON 09 NOV 2026 · 07:12', name: 'Pull A', sets: 16, total: '3,940', duration: '0:48', filter: 'iron', scene: 1, caption: 'Iron' },
  { proof: 40, streakWeeks: 6, time: 'WED 11 NOV 2026 · 18:30', name: 'Legs', sets: 15, total: '6,105', duration: '0:55', filter: 'chalk', scene: 0, caption: 'Chalk' },
  { proof: 41, streakWeeks: 6, time: 'FRI 13 NOV 2026 · 12:05', name: 'Upper', sets: 20, total: '4,410', duration: '1:01', filter: 'plate', scene: 2, caption: 'Plate' },
  { proof: 42, streakWeeks: 7, time: 'SUN 15 NOV 2026 · 18:47', name: 'Push A', sets: 18, total: '6,240', duration: '1:12', filter: 'raw', scene: 3, caption: 'Raw' },
  { proof: 43, streakWeeks: 7, time: 'TUE 17 NOV 2026 · 06:58', name: 'Pull B', sets: 17, total: '4,060', duration: '0:50', filter: 'iron', scene: 2, caption: 'Iron' },
  { proof: 44, streakWeeks: 7, time: 'THU 19 NOV 2026 · 19:20', name: 'Legs', sets: 14, total: '6,350', duration: '0:57', filter: 'plate', scene: 1, caption: 'Plate' },
  { proof: 45, streakWeeks: 7, time: 'SAT 21 NOV 2026 · 10:14', name: 'Full body', sets: 19, total: '5,215', duration: '1:04', filter: 'chalk', scene: 3, caption: 'Chalk' },
  { proof: 46, streakWeeks: 8, time: 'MON 23 NOV 2026 · 07:05', name: 'Push B', sets: 16, total: '4,480', duration: '0:46', filter: 'raw', scene: 0, caption: 'Raw' },
]

const WEEKS = [
  { label: 'Week 5', days: ['on', 'off', 'on', 'off', 'on', 'on', 'off'], status: '4 of 4', hit: true },
  { label: 'Week 6', days: ['on', 'off', 'on', 'off', 'on', 'off', 'off'], status: 'Pass week', hit: true },
  { label: 'Week 7', days: ['on', 'off', 'on', 'off', 'on', 'off', 'on'], status: '4 of 4', hit: true },
  { label: 'Week 8', days: ['off', 'off', 'off', 'off', 'off', 'off', 'off'], status: '0 of 4. New week', hit: false },
]

// Sessions per week over 12 weeks against a goal of 4 (example data).
const CHART = [2, 3, 4, 4, 3, 4, 5, 4, 4, 3, 4, 4]
const GOAL = 4

const FAQ: { q: string; a: ReactNode }[] = [
  {
    q: 'Is it free?',
    a: <p>The price is not set yet. The launch email says what it is before you download anything.</p>,
  },
  {
    q: 'Which phones?',
    a: <p>iPhone, on iOS 17 or later. No Android, iPad or Watch app in the first version.</p>,
  },
  {
    q: 'What happens to my photos?',
    a: (
      <p>
        They are private. They go to one private storage bucket under your account, location data is removed on
        the phone before upload, and nobody sees them unless you share a card. You can delete one photo, all of
        them, or your whole account at any time.
      </p>
    ),
  },
  {
    q: 'How is the physique score made?',
    a: (
      <p>
        Only if you turn it on, and only if you are 18 or older. The session photo is sent to an AI vision model
        that returns a score from 0 to 100 and one training tip. It is compared only with your own earlier scores,
        never shown on the card, and turning it off deletes every stored score. It is an estimate from one photo,
        not medical advice.
      </p>
    ),
  },
  {
    q: 'Why can I not use a photo from my camera roll?',
    a: (
      <p>
        Because then it would not be proof. The photo comes from the camera inside the app, and the time and proof
        number come from the server when it arrives, not from the phone clock.
      </p>
    ),
  },
  {
    q: 'What if I miss a week?',
    a: (
      <p>
        You get a fresh week on Monday. Every four weeks you hit earns a pass week, which is used for you
        automatically, so one bad week does not erase months.
      </p>
    ),
  },
]

export default function Home() {
  return (
    <>
      {/* 2. Hero */}
      <section className="hero" aria-labelledby="hero-title">
        <div className="wrap hero-grid">
          <div className="hero-copy" id="join">
            <span className="label label-plate">An iPhone app</span>
            <h1 id="hero-title" className="display display-xl">
              Proof of gym<span className="dot">.</span>
            </h1>
            <p className="lede">
              Log your sets. Take one photo in the gym. Get a timestamped card with a proof number that only goes up.
            </p>
            <CallToAction source="hero" readQuery />
          </div>
          <div className="hero-visual">
            <div className="hero-stack">
              <ProofCard {...BACK_CARD} className="hero-back" label="" />
              <div className="phone hero-phone">
                <div className="phone-screen">
                  <div className="phone-bar">
                    <span className="label">Session complete</span>
                    <span className="label label-plate">Week 7</span>
                  </div>
                  <div className="phone-card">
                    <ProofCard {...HERO_CARD} animateStamp />
                  </div>
                  <div className="phone-actions" aria-hidden="true">
                    <span className="fake-btn">Share proof</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 3. The loop */}
      <section className="section" aria-labelledby="loop-title">
        <div className="wrap">
          <div className="section-head" data-reveal>
            <span className="label">How it works</span>
            <h2 id="loop-title" className="display display-l">
              Three steps. Under a minute after your last set.
            </h2>
          </div>
          <LoopDemo card={DEMO_CARD} />
        </div>
      </section>

      {/* 4. The card */}
      <section className="section" aria-labelledby="card-title">
        <div className="wrap">
          <div className="section-head" data-reveal>
            <span className="label">The card</span>
            <h2 id="card-title" className="display display-l">
              One layout. Every time.
            </h2>
            <p>
              Same stamp, same place, four filters. A profile full of them reads as a series: the 39th time, the
              40th, the 41st. The number only goes up.
            </p>
          </div>
          <ul className="card-row" aria-label="Example proof cards" data-reveal>
            {EXAMPLE_CARDS.map(({ caption, ...card }) => (
              <li key={card.proof}>
                <figure style={{ margin: 0 }}>
                  <ProofCard {...card} />
                  <figcaption className="label">
                    {caption} · Example
                  </figcaption>
                </figure>
              </li>
            ))}
          </ul>
        </div>
      </section>

      {/* 5. The streak */}
      <section className="section" aria-labelledby="streak-title">
        <div className="wrap split">
          <div className="section-head" data-reveal style={{ marginBottom: 0 }}>
            <span className="label">The streak</span>
            <h2 id="streak-title" className="display display-l">
              Weeks, not days.
            </h2>
            <p>
              You pick the number, from 2 to 6 sessions a week. Hit it and the streak moves. Rest days never break it,
              and every four weeks you hit earns a pass week for the one that goes sideways.
            </p>
          </div>
          <div className="weeks" data-reveal role="img" aria-label="Example: a goal of four sessions a week. Weeks 5 to 7 hit, week 6 used a pass week, week 8 starts fresh at 0 of 4.">
            {WEEKS.map((w) => (
              <div className="week" key={w.label} aria-hidden="true">
                <span className="label">{w.label}</span>
                <span className="rings">
                  {w.days.map((d, i) => (
                    <span key={i} className={`ring${d === 'on' ? ' on' : ''}`} />
                  ))}
                </span>
                <span className={`week-status${w.hit ? ' hit' : ''}`}>{w.status}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* 6. Progress */}
      <section className="section" aria-labelledby="progress-title">
        <div className="wrap">
          <div className="section-head" data-reveal>
            <span className="label">Progress</span>
            <h2 id="progress-title" className="display display-l">
              Every session, on one wall.
            </h2>
            <p>The proof wall keeps every photo in order. The chart shows twelve weeks against your goal.</p>
          </div>
          <div className="progress-grid">
            <div className="panel" data-reveal>
              <span className="label">Proof wall · Example</span>
              <div className="wall" aria-hidden="true">
                {Array.from({ length: 12 }, (_, i) => (
                  <div className="thumb" key={i}>
                    <CardPhoto scene={(i % 4) as Scene} filter={(['iron', 'chalk', 'plate', 'iron'] as const)[i % 4]} />
                    <span>#{String(33 + i).padStart(3, '0')}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="panel" data-reveal>
              <span className="label">Sessions a week · 12 weeks · Example</span>
              <div
                className="chart"
                data-reveal
                role="img"
                aria-label={`Example chart: sessions per week over 12 weeks, goal ${GOAL}. ${CHART.filter((n) => n >= GOAL).length} of 12 weeks hit.`}
              >
                {CHART.map((n, i) => (
                  <span
                    key={i}
                    className={`bar${n >= GOAL ? ' hit' : ''}`}
                    style={{ height: `${(n / 6) * 100}%`, transitionDelay: `${i * 25}ms` }}
                  />
                ))}
              </div>
              <div className="chart-axis" aria-hidden="true">
                <span className="label">W1</span>
                <span className="label">Goal {GOAL} a week</span>
                <span className="label">W12</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 7. Private by default */}
      <section className="section" aria-labelledby="private-title">
        <div className="wrap">
          <div className="section-head" data-reveal>
            <span className="label">Private by default</span>
            <h2 id="private-title" className="display display-l">
              Your photos stay yours.
            </h2>
          </div>
          <ul className="facts">
            <li className="fact" data-reveal>
              <h3>Private until you share</h3>
              <p>Photos sit in private storage under your account. A card leaves the app only when you tap Share.</p>
            </li>
            <li className="fact" data-reveal>
              <h3>The score is opt-in</h3>
              <p>
                Off by default, 18 and over only, and only you see it. It is never on the card. Turn it off and every
                stored score is deleted.
              </p>
            </li>
            <li className="fact" data-reveal>
              <h3>Delete anything</h3>
              <p>
                One photo, all photos, or the whole account, from the app or from{' '}
                <Link href="/delete-account">this site</Link>.
              </p>
            </li>
          </ul>
        </div>
      </section>

      {/* 8. Questions */}
      <section className="section" aria-labelledby="faq-title">
        <div className="wrap">
          <div className="section-head" data-reveal>
            <span className="label">Questions</span>
            <h2 id="faq-title" className="display display-l">
              Asked before you ask.
            </h2>
          </div>
          <div className="faq" data-reveal>
            {FAQ.map((item) => (
              <details key={item.q}>
                <summary>{item.q}</summary>
                <div>{item.a}</div>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* 9. Final call */}
      <section className="section" aria-labelledby="final-title">
        <div className="wrap final" data-reveal>
          <h2 id="final-title" className="display display-xl">
            Show up. <br />
            Get the proof<span style={{ color: 'var(--plate)' }}>.</span>
          </h2>
          <CallToAction source="final-call" />
        </div>
      </section>

      {/* 10. Built in the open */}
      <section className="section" aria-labelledby="open-title">
        <div className="wrap">
          <div className="section-head" data-reveal>
            <span className="label">Built in the open</span>
            <h2 id="open-title" className="display display-l">
              Read the code. Bring your agent.
            </h2>
          </div>
          <div className="open-grid">
            <div className="open-card" data-reveal>
              <h3>The code is on GitHub</h3>
              <p>
                The iPhone app, the server and this site, in one public repository. Read how the proof number is
                made, or run the whole thing on your laptop.
              </p>
              <p className="open-links">
                <a className="btn btn-secondary" href={site.githubUrl}>
                  kon-rad/pgym on GitHub
                </a>
                <Link className="arrow-link" href="/open-source">
                  Open source
                </Link>
              </p>
            </div>
            <div className="open-card" data-reveal>
              <h3>Your agent can read your data</h3>
              <p>
                Make a token in the app and give it to your own AI agent. It can read your sessions, streak and lifts
                to plan next week. Read only: it cannot make a proof. Photos need their own permission.
              </p>
              <div className="code" aria-label="Example request">
                {`curl -H "Authorization: Bearer $PGYM_TOKEN" \\\n  ${site.apiUrl}/v1/stats`}
              </div>
              <p className="open-links">
                <Link className="arrow-link" href="/agents">
                  For your agent
                </Link>
                <a className="arrow-link" href="/skill.md">
                  skill.md
                </a>
              </p>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
