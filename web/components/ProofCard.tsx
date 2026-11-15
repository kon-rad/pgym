import { useId } from 'react'
import { Lockup } from './Logo'

// A proof card drawn in HTML and SVG: the layout from pgym-design-style.md
// ("The proof card"). The photo is an illustration of a loaded barbell, not a
// photo of a person, so the site carries no real user data. Filters are applied
// to the photo only, never to the text, as in the app.

export type CardFilter = 'iron' | 'chalk' | 'plate' | 'raw'

export interface ProofCardProps {
  proof: number
  week: number
  time: string
  name: string
  sets: number
  kg: string
  duration: string
  filter?: CardFilter
  scene?: 0 | 1 | 2 | 3
  small?: boolean
  animateStamp?: boolean
  /** Text read by screen readers in place of the drawing. */
  label?: string
}

export function Stamp({ top, big, bottom, animate }: { top: string; big: string; bottom: string; animate?: boolean }) {
  return (
    <div className={`stamp${animate ? ' stamp-animate' : ''}`} aria-hidden="true">
      <span className="stamp-label">{top}</span>
      <span className="stamp-num">{big}</span>
      <span className="stamp-week">{bottom}</span>
    </div>
  )
}

export function proofLabel(proof: number): string {
  return `#${String(proof).padStart(3, '0')}`
}

function Grain() {
  const id = `grain${useId().replace(/[^a-zA-Z0-9_-]/g, '')}`
  return (
    <svg className="card-grain" aria-hidden="true" preserveAspectRatio="none">
      <filter id={id}>
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" />
        <feColorMatrix type="saturate" values="0" />
      </filter>
      <rect width="100%" height="100%" filter={`url(#${id})`} />
    </svg>
  )
}

/** Four gym scenes, all objects: a barbell, a rack, dumbbells, a plate tree. */
function Scene({ variant }: { variant: number }) {
  const wall = ['#3a3d44', '#46423c', '#2f3439', '#3d3a41'][variant]
  const floor = ['#26241f', '#2b2620', '#1f2226', '#2a2522'][variant]
  const plate = '#141416'
  const rim = '#2b2c31'
  const steel = '#b9bcc2'
  return (
    <svg viewBox="0 0 400 500" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
      <rect width="400" height="500" fill={wall} />
      {/* window light on the wall */}
      <rect x="230" y="40" width="130" height="190" fill="#f2efe8" opacity="0.10" />
      <rect x="292" y="40" width="4" height="190" fill={wall} opacity="0.6" />
      <rect y="300" width="400" height="200" fill={floor} />
      <rect y="300" width="400" height="4" fill="#000" opacity="0.35" />
      {variant === 0 && (
        <g>
          {/* barbell on the floor, plates loaded */}
          <rect x="10" y="337" width="380" height="7" rx="3" fill={steel} />
          {[38, 72, 328, 362].map((x) => (
            <g key={x}>
              <ellipse cx={x} cy="340" rx="20" ry="72" fill={plate} />
              <ellipse cx={x} cy="340" rx="14" ry="54" fill="none" stroke={rim} strokeWidth="3" />
            </g>
          ))}
          <ellipse cx="200" cy="420" rx="180" ry="10" fill="#000" opacity="0.35" />
        </g>
      )}
      {variant === 1 && (
        <g>
          {/* squat rack with a bar in the hooks */}
          <rect x="70" y="60" width="16" height="300" fill="#1c1c1f" />
          <rect x="314" y="60" width="16" height="300" fill="#1c1c1f" />
          <rect x="70" y="60" width="260" height="14" fill="#1c1c1f" />
          {Array.from({ length: 10 }, (_, i) => (
            <circle key={i} cx="78" cy={100 + i * 24} r="3" fill={wall} />
          ))}
          <rect x="20" y="188" width="360" height="7" rx="3" fill={steel} />
          {[44, 356].map((x) => (
            <g key={x}>
              <ellipse cx={x} cy="191" rx="16" ry="62" fill={plate} />
              <ellipse cx={x} cy="191" rx="11" ry="46" fill="none" stroke={rim} strokeWidth="3" />
            </g>
          ))}
        </g>
      )}
      {variant === 2 && (
        <g>
          {/* dumbbell rack */}
          <rect x="30" y="250" width="340" height="12" fill="#121214" />
          <rect x="30" y="330" width="340" height="12" fill="#121214" />
          {[60, 140, 220, 300].map((x, i) => (
            <g key={x}>
              <rect x={x} y={226 - i * 2} width="60" height="8" fill={steel} />
              <rect x={x - 6} y={214 - i * 2} width="20" height={32 + i * 4} rx="4" fill={plate} />
              <rect x={x + 46} y={214 - i * 2} width="20" height={32 + i * 4} rx="4" fill={plate} />
              <rect x={x} y={306 - i * 2} width="60" height="8" fill={steel} />
              <rect x={x - 6} y={292 - i * 2} width="20" height={36 + i * 4} rx="4" fill={plate} />
              <rect x={x + 46} y={292 - i * 2} width="20" height={36 + i * 4} rx="4" fill={plate} />
            </g>
          ))}
        </g>
      )}
      {variant === 3 && (
        <g>
          {/* plate tree */}
          <rect x="194" y="120" width="12" height="250" fill="#1c1c1f" />
          <rect x="150" y="360" width="100" height="14" rx="4" fill="#1c1c1f" />
          {[
            [160, 170, 58],
            [240, 210, 66],
            [158, 270, 72],
            [242, 300, 50],
          ].map(([x, y, r]) => (
            <g key={`${x}-${y}`}>
              <circle cx={x} cy={y} r={r} fill={plate} />
              <circle cx={x} cy={y} r={r * 0.72} fill="none" stroke={rim} strokeWidth="4" />
              <circle cx={x} cy={y} r="8" fill={rim} />
            </g>
          ))}
        </g>
      )}
    </svg>
  )
}

/** Just the photo layer of a card, for the camera viewfinder and the proof wall. */
export function CardPhoto({ scene = 0 }: { scene?: 0 | 1 | 2 | 3 }) {
  return (
    <div className="card-photo" aria-hidden="true">
      <Scene variant={scene} />
    </div>
  )
}

export function ProofCard(p: ProofCardProps) {
  const filter = p.filter ?? 'iron'
  return (
    <div
      className={`card filter-${filter}${p.small ? ' card-sm' : ''}`}
      role="img"
      aria-label={
        p.label ??
        `Example proof card number ${p.proof}: ${p.name}, ${p.time}, ${p.sets} sets, ${p.kg} kilograms, ${p.duration}. Week ${p.week}.`
      }
    >
      <div className="card-photo">
        <Scene variant={p.scene ?? 0} />
      </div>
      <Grain />
      <div className="card-scrim" />
      <div className="card-top" aria-hidden="true">
        <Lockup height={p.small ? 12 : 18} label={false} />
        <Stamp top="PROOF" big={proofLabel(p.proof)} bottom={`WEEK ${p.week}`} animate={p.animateStamp} />
      </div>
      <div className="card-bottom" aria-hidden="true">
        <div className="card-time">{p.time}</div>
        <div className="card-name">{p.name}</div>
        <dl className="card-stats">
          <div>
            <dt>Sets</dt>
            <dd>{p.sets}</dd>
          </div>
          <div>
            <dt>Kg lifted</dt>
            <dd>{p.kg}</dd>
          </div>
          <div>
            <dt>Time</dt>
            <dd>{p.duration}</dd>
          </div>
        </dl>
      </div>
    </div>
  )
}
