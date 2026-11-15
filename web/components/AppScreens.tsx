import type { ReactNode } from 'react'
import { CardPhoto, ProofCard, type CardFilter, type ProofCardProps, type Scene } from './ProofCard'

// Phone frames and the app screens the home page shows, rebuilt in HTML from the
// view list in pgym-app-views.md until the simulator screenshots (assets S1 to
// S6 in pgym-landing-design.md 6) exist. Every screen is drawn on the seeded
// demo account: routine "Push A", proof #042, 7 weeks running, kg, analysis off.
// No screen has a physique score row: marketing never shows the score.
//
// A frame is drawn in CSS (pgym-landing-design.md 1, "Phone frames"): an 8 px
// Rail border, 40 px outer radius, and a screen at the 1320 x 2868 capture
// aspect. Screen contents are sized in em of a font size set from the frame
// width, so one drawing fits frameS (200 px), frameM (240 px) and frameL (320 px).

export type FrameSize = 's' | 'm' | 'l'

export function Phone({
  size,
  desktop,
  label,
  className,
  children,
}: {
  /** Frame at 390 px. */
  size: FrameSize
  /** Frame from 768 px, if different. */
  desktop?: FrameSize
  /** What a screen reader hears in place of the drawing. */
  label: string
  className?: string
  children: ReactNode
}) {
  const classes = ['phone', `phone-${size}`, desktop ? `phone-up-${desktop}` : '', className ?? ''].filter(Boolean)
  return (
    <figure className={classes.join(' ')} role="img" aria-label={label}>
      <div className="phone-screen" aria-hidden="true">
        <div className="scr">
          <StatusBar />
          {children}
        </div>
      </div>
    </figure>
  )
}

/** The cleaned status bar of an App Store screenshot: 9:41, full signal and battery. */
function StatusBar() {
  return (
    <div className="scr-status">
      <span>9:41</span>
      <span className="scr-status-icons">
        <span className="scr-signal">
          <i />
          <i />
          <i />
          <i />
        </span>
        <span className="scr-battery" />
      </span>
    </div>
  )
}

function Tick() {
  return (
    <svg viewBox="0 0 14 14" aria-hidden="true">
      <path d="M2.5 7.5 5.5 10.5 11.5 3.5" fill="none" stroke="#0B0B0C" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

const FILTERS: CardFilter[] = ['iron', 'chalk', 'plate', 'raw']

/** D8 Proof card editor: the card preview, 4:5 selected, the four filters with Iron on, Retake and Stamp it. */
export function EditorScreen({ card }: { card: ProofCardProps }) {
  return (
    <div className="scr-body">
      <div className="scr-bar">
        <span className="scr-label">Push A</span>
        <span className="scr-label">Proof card</span>
      </div>
      <ProofCard {...card} label="" />
      <div className="scr-seg">
        <span className="on">4:5</span>
        <span>9:16</span>
      </div>
      <div className="scr-chips">
        {FILTERS.map((f) => (
          <span key={f} className={f === card.filter ? 'on' : undefined}>
            {f}
          </span>
        ))}
      </div>
      <div className="scr-actions">
        <span className="scr-btn scr-btn-2">Retake</span>
        <span className="scr-btn">Stamp it</span>
      </div>
    </div>
  )
}

const SETS: [n: string, kg: string, reps: string][] = [
  ['1', '60', '8'],
  ['2', '80', '6'],
  ['3', '80', '6'],
]

/**
 * D2 Active session: routine "Push A", one exercise done and collapsed, the
 * current exercise with set rows, the rest timer, Up next, and Finish and take
 * proof. The three checks carry the loop sequence's classes (ld-check-*).
 */
export function SessionScreen() {
  return (
    <div className="scr-body ld-frame-log">
      <div className="scr-bar">
        <span className="scr-label">Push A</span>
        <span className="scr-label scr-data">42:10</span>
      </div>
      <div className="scr-done">
        <span className="scr-check done">
          <Tick />
        </span>
        <span>Overhead press</span>
        <span className="scr-label">3 sets</span>
      </div>
      <p className="scr-title">Bench press</p>
      {SETS.map(([n, kg, reps], i) => (
        <div className="scr-set" key={n}>
          <span className="scr-n">{n}</span>
          <span>
            {kg} <small>KG</small>
          </span>
          <span>
            {reps} <small>REPS</small>
          </span>
          <span className={`scr-check ld-check ld-check-${i + 1}`}>
            <Tick />
          </span>
        </div>
      ))}
      <div className="scr-set">
        <span className="scr-n">4</span>
        <span>
          80 <small>KG</small>
        </span>
        <span>
          6 <small>REPS</small>
        </span>
        <span className="scr-check" />
      </div>
      <div className="scr-rest">
        <span className="scr-label">Rest</span>
        <span className="scr-track">
          <span className="ld-rest" />
        </span>
        <span className="scr-data">1:30</span>
      </div>
      <p className="scr-next">
        <span className="scr-label">Up next</span> Incline dumbbell press
      </p>
      <span className="scr-btn ld-finish">Finish and take proof</span>
    </div>
  )
}

/** D7 Proof camera: the back camera on the gym, timer off, no framing lines, nothing left of the shutter. */
export function CameraScreen() {
  return (
    <div className="scr-camera ld-frame-photo">
      <div className="scr-viewfinder">
        <CardPhoto scene={0} />
        <div className="ld-flash" />
      </div>
      <div className="scr-camera-top">
        <span className="scr-round">×</span>
        <span className="scr-label">Timer off</span>
      </div>
      <div className="scr-camera-bottom">
        <span />
        <span className="scr-shutter ld-shutter" />
        <span className="scr-round scr-flip">⟲</span>
      </div>
    </div>
  )
}

/** The week row's days, Monday first: four done, three to go. */
export const WEEK_DAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'] as const
export const WEEK_DONE = [true, false, true, false, true, true, false] as const

/** D11 Session complete, analysis off and no offer row: the stamped card, "Week 7 locked.", the week, a new best, Share proof. */
export function CompleteScreen({ card }: { card: ProofCardProps }) {
  return (
    <div className="scr-body ld-frame-card">
      <ProofCard {...card} label="" />
      <p className="scr-display">Week 7 locked.</p>
      <div className="scr-rings">
        {WEEK_DONE.map((done, i) => (
          <span key={i} className={done ? 'on' : undefined}>
            {done ? <Tick /> : null}
          </span>
        ))}
      </div>
      <div className="scr-best">
        <span className="scr-label scr-plate">New best</span>
        <span>Bench press 80 kg × 6</span>
      </div>
      <span className="scr-btn">Share proof</span>
    </div>
  )
}

/** Sessions a week over 12 weeks against a goal of 4 (example data). */
export const CHART = [2, 3, 4, 4, 3, 4, 5, 4, 4, 3, 4, 4]
export const GOAL = 4

const WALL: { proof: number; scene: Scene; filter: CardFilter }[] = Array.from({ length: 18 }, (_, i) => ({
  proof: 42 - i,
  scene: (i % 4) as Scene,
  filter: FILTERS[i % 4],
}))

function Thumb({ proof, scene, filter }: { proof: number; scene: Scene; filter: CardFilter }) {
  return (
    <span className="scr-thumb">
      <CardPhoto scene={scene} filter={filter} />
      <b>#{String(proof).padStart(3, '0')}</b>
    </span>
  )
}

/** E1 Progress with the analysis off: proofs and streak, the 12-week bars, the proof wall preview, two lifts. */
export function ProgressScreen() {
  return (
    <div className="scr-body">
      <p className="scr-display">Progress</p>
      <div className="scr-tiles">
        <span>
          <small>Proofs</small>
          <b>42</b>
        </span>
        <span>
          <small>Streak</small>
          <b>
            7 <small>WK</small>
          </b>
        </span>
      </div>
      <div className="scr-chart">
        <span className="scr-goal" style={{ bottom: `${(GOAL / 6) * 100}%` }} />
        {CHART.map((n, i) => (
          <span key={i} className={`scr-bar-v${n >= GOAL ? ' hit' : ''}`} style={{ height: `${(n / 6) * 100}%` }} />
        ))}
      </div>
      <span className="scr-label">Proof wall</span>
      <div className="scr-wall">
        {WALL.slice(0, 6).map((t) => (
          <Thumb key={t.proof} {...t} />
        ))}
      </div>
      <div className="scr-lift">
        <span>Bench press</span>
        <span className="scr-data">80 × 6</span>
      </div>
      <div className="scr-lift">
        <span>Back squat</span>
        <span className="scr-data">100 × 5</span>
      </div>
    </div>
  )
}

/** E2 Proof wall: every card in a grid, newest first, grouped by month. */
export function ProofWallScreen() {
  return (
    <div className="scr-body">
      <p className="scr-display">Proof wall</p>
      <span className="scr-label">November 2026</span>
      <div className="scr-wall">
        {WALL.slice(0, 9).map((t) => (
          <Thumb key={t.proof} {...t} />
        ))}
      </div>
      <span className="scr-label">October 2026</span>
      <div className="scr-wall">
        {WALL.slice(9).map((t) => (
          <Thumb key={t.proof} {...t} />
        ))}
      </div>
    </div>
  )
}
