import { CardPhoto, ProofCard, type ProofCardProps } from './ProofCard'

// The home page's "log, photo, card" sequence: one phone that plays the loop in
// 9 seconds (sets check off, the shutter fires, the card is stamped), with the
// three steps beside it lighting up in time. CSS only, no JavaScript: every
// element shares one 9 s timeline (see "Loop demo" in globals.css). Each change
// between screens takes 270 ms; the stamp landing is the one longer moment.
// It waits until it scrolls into view, and with Reduce Motion it is a still
// picture of the finished card.

export const LOOP_STEPS = [
  {
    title: 'Log your sets',
    body: "Last session's weights are already filled in. One tap per set. Start a session in two taps.",
  },
  {
    title: 'Take one photo',
    body: "In the app's own camera, at the gym. No camera roll, so every card is from the day it says.",
  },
  {
    title: 'Get your proof',
    body: 'The server stamps the time and the next proof number. Pick a filter and share it anywhere.',
  },
] as const

const SETS: [n: string, kg: string, reps: string][] = [
  ['1', '60', '8'],
  ['2', '80', '6'],
  ['3', '80', '6'],
]

function Tick() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true">
      <path
        d="M2.5 7.5 5.5 10.5 11.5 3.5"
        fill="none"
        stroke="#0B0B0C"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function LoopDemo({ card }: { card: ProofCardProps }) {
  return (
    <div className="loop" data-reveal>
      <figure
        className="loop-phone phone"
        role="img"
        aria-label="An animation of the loop: three sets are checked off, the in-app camera takes one photo, and the proof card is stamped with its number."
      >
        <div className="phone-screen loop-screen" aria-hidden="true">
          <div className="loop-frame ld-frame-log">
            <div className="loop-bar">
              <span className="label">Push A</span>
              <span className="label">18:02</span>
            </div>
            <span className="loop-exercise">Bench press</span>
            {SETS.map(([n, kg, reps], i) => (
              <div className="set-row" key={n}>
                <span className="n">{n}</span>
                <span>
                  {kg} <span className="unit">KG</span>
                </span>
                <span>
                  {reps} <span className="unit">REPS</span>
                </span>
                <span className={`check ld-check ld-check-${i + 1}`}>
                  <Tick />
                </span>
              </div>
            ))}
            <div className="set-row">
              <span className="n">4</span>
              <span>
                80 <span className="unit">KG</span>
              </span>
              <span>
                6 <span className="unit">REPS</span>
              </span>
              <span className="check" />
            </div>
            <span className="fake-btn loop-cta">Finish and take proof</span>
          </div>

          <div className="loop-frame ld-frame-photo">
            <div className="viewfinder loop-viewfinder">
              <CardPhoto scene={0} />
              <div className="corners" />
              <div className="ld-flash" />
            </div>
            <div className="loop-shutter-row">
              <span className="label">Photo</span>
              <span className="shutter ld-shutter" />
              <span className="label">3s</span>
            </div>
          </div>

          <div className="loop-frame ld-frame-card">
            <ProofCard {...card} label="" />
            <span className="fake-btn">Share proof</span>
          </div>
        </div>
      </figure>

      <ol className="loop-steps">
        {LOOP_STEPS.map((step, i) => (
          <li className={`loop-step ld-step-${i + 1}`} key={step.title}>
            <span className="loop-step-n" aria-hidden="true">
              {i + 1}
            </span>
            <div>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </div>
  )
}
