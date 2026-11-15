import Link from 'next/link'
import type { ReactNode } from 'react'
import { CallToAction } from '@/components/CallToAction'
import { CardPhoto, ProofCard, type ProofCardProps } from '@/components/ProofCard'
import { site } from '@/lib/site'

// Home. Sections in the order of pgym-landing-pages.md, "Home page sections".
// Copy follows the voice in pgym-design-style.md: short, flat, a little dry, no
// exclamation marks, no guilt. Every number on an example card is labelled as an
// example; there are no user counts, ratings or testimonials.

const HERO_CARD: ProofCardProps = {
  proof: 42,
  week: 7,
  time: 'SUN 15 NOV 2026 · 18:47',
  name: 'Push A',
  sets: 18,
  kg: '4,820',
  duration: '52:10',
  filter: 'iron',
  scene: 0,
}

const EXAMPLE_CARDS: (ProofCardProps & { caption: string })[] = [
  { proof: 39, week: 6, time: 'MON 09 NOV 2026 · 07:12', name: 'Pull A', sets: 16, kg: '3,940', duration: '48:02', filter: 'iron', scene: 1, caption: 'Iron' },
  { proof: 40, week: 6, time: 'WED 11 NOV 2026 · 18:30', name: 'Legs', sets: 15, kg: '6,105', duration: '55:41', filter: 'chalk', scene: 0, caption: 'Chalk' },
  { proof: 41, week: 6, time: 'FRI 13 NOV 2026 · 12:05', name: 'Upper', sets: 20, kg: '4,410', duration: '61:15', filter: 'plate', scene: 2, caption: 'Plate' },
  { proof: 42, week: 7, time: 'SUN 15 NOV 2026 · 18:47', name: 'Push A', sets: 18, kg: '4,820', duration: '52:10', filter: 'raw', scene: 3, caption: 'Raw' },
  { proof: 43, week: 7, time: 'TUE 17 NOV 2026 · 06:58', name: 'Pull B', sets: 17, kg: '4,060', duration: '50:33', filter: 'iron', scene: 2, caption: 'Iron' },
  { proof: 44, week: 7, time: 'THU 19 NOV 2026 · 19:20', name: 'Legs', sets: 14, kg: '6,350', duration: '57:08', filter: 'plate', scene: 1, caption: 'Plate' },
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
            <div className="phone">
              <div className="phone-screen">
                <div className="phone-bar">
                  <span className="label">Session complete</span>
                  <span className="label label-plate">Week 7</span>
                </div>
                <div style={{ padding: '0 12px' }}>
                  <ProofCard {...HERO_CARD} animateStamp />
                </div>
                <div className="phone-actions" aria-hidden="true">
                  <span className="fake-btn">Share proof</span>
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
          <ol className="steps">
            <li className="step" data-reveal>
              <div className="screen" aria-hidden="true">
                <span className="label">Bench press</span>
                {[
                  ['1', '60', '8', true],
                  ['2', '80', '6', true],
                  ['3', '80', '6', true],
                  ['4', '80', '6', false],
                ].map(([n, kg, reps, done]) => (
                  <div className="set-row" key={String(n)}>
                    <span className="n">{n}</span>
                    <span>
                      {kg} <span className="unit">KG</span>
                    </span>
                    <span>
                      {reps} <span className="unit">REPS</span>
                    </span>
                    <span className={`check${done ? ' done' : ''}`}>
                      {done ? (
                        <svg width="14" height="14" viewBox="0 0 14 14">
                          <path d="M2.5 7.5 5.5 10.5 11.5 3.5" fill="none" stroke="#0B0B0C" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
                        </svg>
                      ) : null}
                    </span>
                  </div>
                ))}
              </div>
              <h3>Log your sets</h3>
              <p>Last session&apos;s weights are already filled in. One tap per set. Start a session in two taps.</p>
            </li>
            <li className="step" data-reveal>
              <div className="screen" aria-hidden="true">
                <div className="viewfinder">
                  <div className="card filter-raw" style={{ position: 'absolute', inset: 0, borderRadius: 0 }}>
                    <CardPhoto scene={2} />
                  </div>
                  <div className="corners" />
                  <div className="shutter" />
                </div>
              </div>
              <h3>Take one photo</h3>
              <p>In the app&apos;s own camera, at the gym. No camera roll, so every card is from the day it says.</p>
            </li>
            <li className="step" data-reveal>
              <div className="screen" aria-hidden="true">
                <ProofCard {...HERO_CARD} small filter="plate" scene={1} label="" />
              </div>
              <h3>Get your proof</h3>
              <p>The server stamps the time and the next proof number. Pick a filter and share it anywhere.</p>
            </li>
          </ol>
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
                  <ProofCard {...card} small />
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
                  <div className={`thumb card filter-${(['iron', 'chalk', 'plate', 'iron'] as const)[i % 4]}`} key={i}>
                    <CardPhoto scene={(i % 4) as 0 | 1 | 2 | 3} />
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
              <p>
                <a className="btn btn-secondary" href={site.githubUrl}>
                  kon-rad/pgym on GitHub
                </a>
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
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
