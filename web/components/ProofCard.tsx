import { useId } from 'react'
import { layoutName, proofLabel, stampNumberSize, streakLine } from '@/lib/proof-card'
import { LETTER_PATHS, MONO_PATHS } from './Logo'

// The proof card, drawn from the 4:5 template (Areas/PGYM/design/proof-card/
// pgym-card-4x5.svg) at its own coordinates: a 1080 x 1350 viewBox that scales
// to any width. Photo, 75% Ink scrim over the lower 55%, the wordmark chip, the
// solid Ink stamp rotated 4 degrees anticlockwise with the mono mark inside, the
// timestamp, the session name and the stat row. Filters touch the photo only.
//
// The photo is an illustration of gym equipment, not a photo of a person, so the
// site carries no real user data. The physique score has no prop here, so it
// cannot end up on a card.

export type CardFilter = 'iron' | 'chalk' | 'plate' | 'raw'
export type Scene = 0 | 1 | 2 | 3

export interface ProofCardProps {
  proof: number
  /** Weeks in the current streak. 0 reads "NEW STREAK". */
  streakWeeks: number
  /** Server time, "SUN 15 NOV 2026 · 18:47". */
  time: string
  /** Session name, upper-cased and fitted to two lines. */
  name: string
  sets: number
  /** Total lifted, already grouped: "6,240". */
  total: string
  unit?: 'KG' | 'LB'
  /** Duration as h:mm, "1:12". */
  duration: string
  filter?: CardFilter
  scene?: Scene
  /** Play the stamp landing once on load. */
  animateStamp?: boolean
  /** Text read by screen readers in place of the drawing. Empty hides the card from them. */
  label?: string
  className?: string
}

const INK = '#0B0B0C'
const CHALK = '#F2EFE8'
const PLATE = '#FF4D1F'

function contrast(c: number, brightness = 0): { slope: number; intercept: number } {
  return { slope: c, intercept: 0.5 * (1 - c) + brightness }
}

function Linear({ c, b = 0 }: { c: number; b?: number }) {
  const { slope, intercept } = contrast(c, b)
  return (
    <feComponentTransfer>
      <feFuncR type="linear" slope={slope} intercept={intercept} />
      <feFuncG type="linear" slope={slope} intercept={intercept} />
      <feFuncB type="linear" slope={slope} intercept={intercept} />
    </feComponentTransfer>
  )
}

/**
 * The four filters from the spec's filter table, as SVG filter chains. Values
 * follow the Core Image parameters: Iron is mono, contrast 1.25, brightness
 * -0.02 and soft-light grain; Chalk is the warm matrix, saturation 0.92,
 * contrast 0.88 and the lifted tone curve; Plate is mono at contrast 1.15,
 * false-coloured Ink to Plate, dissolved 85% over the mono.
 */
export function PhotoFilter({ id, filter }: { id: string; filter: CardFilter }) {
  if (filter === 'raw') return null
  if (filter === 'iron') {
    return (
      <filter id={id} x="0" y="0" width="1" height="1" colorInterpolationFilters="sRGB">
        <feColorMatrix type="saturate" values="0" />
        <Linear c={1.25} b={-0.02} />
        <feComponentTransfer result="photo">
          <feFuncA type="identity" />
        </feComponentTransfer>
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" />
        <feColorMatrix type="matrix" values="0 0.12 0 0 0.44  0 0.12 0 0 0.44  0 0.12 0 0 0.44  0 0 0 0 1" result="grain" />
        <feBlend in="grain" in2="photo" mode="soft-light" />
      </filter>
    )
  }
  if (filter === 'chalk') {
    return (
      <filter id={id} x="0" y="0" width="1" height="1" colorInterpolationFilters="sRGB">
        <feColorMatrix type="matrix" values="1.04 0 0 0 0  0 1 0 0 0  0 0 0.94 0 0  0 0 0 1 0" />
        <feColorMatrix type="saturate" values="0.92" />
        <Linear c={0.88} b={0.02} />
        <feComponentTransfer>
          <feFuncR type="table" tableValues="0.08 0.28 0.52 0.76 0.97" />
          <feFuncG type="table" tableValues="0.08 0.28 0.52 0.76 0.97" />
          <feFuncB type="table" tableValues="0.08 0.28 0.52 0.76 0.97" />
        </feComponentTransfer>
      </filter>
    )
  }
  return (
    <filter id={id} x="0" y="0" width="1" height="1" colorInterpolationFilters="sRGB">
      <feColorMatrix type="saturate" values="0" />
      <feComponentTransfer result="mono">
        <feFuncR type="linear" slope="1.15" intercept="-0.075" />
        <feFuncG type="linear" slope="1.15" intercept="-0.075" />
        <feFuncB type="linear" slope="1.15" intercept="-0.075" />
      </feComponentTransfer>
      <feComponentTransfer in="mono" result="duo">
        <feFuncR type="table" tableValues="0.043 1" />
        <feFuncG type="table" tableValues="0.043 0.302" />
        <feFuncB type="table" tableValues="0.047 0.122" />
      </feComponentTransfer>
      <feComposite in="mono" in2="duo" operator="arithmetic" k1="0" k2="0.15" k3="0.85" k4="0" />
    </filter>
  )
}

/** Four gym scenes, all objects: a barbell, a rack, dumbbells, a plate tree. 400 x 500 units. */
function SceneArt({ variant, uid }: { variant: Scene; uid: string }) {
  const wall = ['#4a4e57', '#5a5248', '#3c434b', '#4d4852'][variant]
  const floor = ['#2b2822', '#302a22', '#22262b', '#2e2925'][variant]
  const plate = '#141416'
  const rim = '#34353b'
  const steel = '#c7cad0'
  const light = `${uid}-light`
  const vignette = `${uid}-vig`
  return (
    <g>
      <defs>
        <radialGradient id={light} cx="0.68" cy="0.22" r="0.75">
          <stop offset="0" stopColor="#fff6e6" stopOpacity="0.32" />
          <stop offset="0.5" stopColor="#fff6e6" stopOpacity="0.08" />
          <stop offset="1" stopColor="#fff6e6" stopOpacity="0" />
        </radialGradient>
        <radialGradient id={vignette} cx="0.5" cy="0.45" r="0.8">
          <stop offset="0.55" stopColor="#000" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.55" />
        </radialGradient>
      </defs>
      <rect width="400" height="500" fill={wall} />
      {/* window light and the window frame on the wall */}
      <rect x="230" y="40" width="130" height="190" fill="#f2efe8" opacity="0.16" />
      <rect x="292" y="40" width="4" height="190" fill={wall} opacity="0.7" />
      <rect x="230" y="132" width="130" height="4" fill={wall} opacity="0.7" />
      {/* rubber floor with tile seams */}
      <rect y="300" width="400" height="200" fill={floor} />
      {[0, 1, 2, 3].map((i) => (
        <rect key={i} x={i * 110 - 20} y="300" width="2" height="200" fill="#000" opacity="0.25" />
      ))}
      <rect y="300" width="400" height="4" fill="#000" opacity="0.4" />
      {variant === 0 && (
        <g>
          <ellipse cx="200" cy="420" rx="190" ry="14" fill="#000" opacity="0.4" />
          <rect x="10" y="337" width="380" height="7" rx="3" fill={steel} />
          <rect x="10" y="337" width="380" height="2" fill="#fff" opacity="0.35" />
          {[38, 72, 328, 362].map((x) => (
            <g key={x}>
              <ellipse cx={x} cy="340" rx="20" ry="72" fill={plate} />
              <ellipse cx={x} cy="340" rx="14" ry="54" fill="none" stroke={rim} strokeWidth="3" />
              <ellipse cx={x - 6} cy="312" rx="4" ry="22" fill="#fff" opacity="0.08" />
            </g>
          ))}
        </g>
      )}
      {variant === 1 && (
        <g>
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
          <ellipse cx="200" cy="364" rx="150" ry="8" fill="#000" opacity="0.35" />
        </g>
      )}
      {variant === 2 && (
        <g>
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
          <ellipse cx="200" cy="378" rx="90" ry="8" fill="#000" opacity="0.35" />
        </g>
      )}
      <rect width="400" height="500" fill={`url(#${light})`} />
      <rect width="400" height="500" fill={`url(#${vignette})`} />
    </g>
  )
}

function useSvgId(prefix: string): string {
  return `${prefix}${useId().replace(/[^a-zA-Z0-9_-]/g, '')}`
}

/** Just the photo layer, filtered: for the camera viewfinder and the proof wall. */
export function CardPhoto({ scene = 0, filter = 'raw' }: { scene?: Scene; filter?: CardFilter }) {
  const uid = useSvgId('ph')
  return (
    <svg className="card-photo" viewBox="0 0 400 500" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
      <defs>
        <PhotoFilter id={`${uid}-f`} filter={filter} />
      </defs>
      <g filter={filter === 'raw' ? undefined : `url(#${uid}-f)`}>
        <SceneArt variant={scene} uid={uid} />
      </g>
    </svg>
  )
}

/** The card stamp: solid Ink box, 4 px Plate outline, mono mark upright, three lines of Plate. */
export function CardStamp({ proof, streakWeeks, animate }: { proof: number; streakWeeks: number; animate?: boolean }) {
  const number = proofLabel(proof)
  return (
    <g transform="rotate(-4 882 118)">
      <g className={`pc-stamp${animate ? ' pc-stamp-animate' : ''}`}>
        <rect x="734" y="50" width="296" height="136" rx="4" fill={INK} stroke={PLATE} strokeWidth="4" />
        <g transform="translate(792 118) scale(0.11)" fill="none" stroke={PLATE}>
          {MONO_PATHS}
        </g>
        <text x="852" y="86" className="pc-mono" fill={PLATE} fontSize="18" letterSpacing="1.5">
          PROOF
        </text>
        <text x="852" y="146" className="pc-display" fill={PLATE} fontSize={stampNumberSize(number)}>
          {number}
        </text>
        <text x="852" y="170" className="pc-mono" fill={PLATE} fontSize="14" letterSpacing="1">
          {streakLine(streakWeeks, proof)}
        </text>
      </g>
    </g>
  )
}

export function describeCard(p: ProofCardProps): string {
  return `Example proof card ${proofLabel(p.proof)}: ${p.name}, ${p.time}. ${p.sets} sets, ${p.total} ${(p.unit ?? 'KG').toLowerCase()} lifted, time ${p.duration}. ${streakLine(p.streakWeeks, p.proof).toLowerCase()}.`
}

export function ProofCard(p: ProofCardProps) {
  const uid = useSvgId('pc')
  const filter = p.filter ?? 'iron'
  const unit = p.unit ?? 'KG'
  const name = layoutName(p.name)
  const label = p.label ?? describeCard(p)
  return (
    <div className={`pcard${p.className ? ` ${p.className}` : ''}`}>
      <svg
        className="pcard-svg"
        viewBox="0 0 1080 1350"
        role={label ? 'img' : undefined}
        aria-label={label || undefined}
        aria-hidden={label ? undefined : true}
      >
        <defs>
          <PhotoFilter id={`${uid}-f`} filter={filter} />
        </defs>

        {/* 1. Photo, aspect fill */}
        <rect width="1080" height="1350" fill="#2A2A2F" />
        <svg x="0" y="0" width="1080" height="1350" viewBox="0 0 400 500" preserveAspectRatio="xMidYMid slice">
          <g filter={filter === 'raw' ? undefined : `url(#${uid}-f)`}>
            <SceneArt variant={p.scene ?? 0} uid={uid} />
          </g>
        </svg>

        {/* 2. Scrim: flat Ink at 75% over the lower 55% */}
        <rect x="0" y="608" width="1080" height="742" fill={INK} fillOpacity="0.75" />

        {/* 3. Wordmark chip */}
        <rect x="48" y="48" width="156" height="68" rx="6" fill={INK} />
        <g transform="translate(64.8 62) scale(0.2)" fill={CHALK} fillRule="evenodd">
          {LETTER_PATHS}
        </g>

        {/* 4. Stamp */}
        <CardStamp proof={p.proof} streakWeeks={p.streakWeeks} animate={p.animateStamp} />

        {/* 5. Lower block, Chalk only */}
        <g fill={CHALK}>
          <text x="64" y={name.timeBaseline} className="pc-mono" fontSize="28" letterSpacing="2">
            {p.time}
          </text>
          {name.lines.map((line, i) => (
            <text key={i} x="64" y={name.baselines[i]} className="pc-display" fontSize={name.size}>
              {line}
            </text>
          ))}
          <text x="64" y="1208" className="pc-mono" fontSize="60">
            {p.sets}
          </text>
          <text x="392" y="1208" className="pc-mono" fontSize="60">
            {p.total}
            <tspan dx="8" fontSize="24" letterSpacing="2">
              {unit}
            </tspan>
          </text>
          <text x="720" y="1208" className="pc-mono" fontSize="60">
            {p.duration}
          </text>
          <rect x="64" y="1232" width="952" height="3" />
          <text x="64" y="1278" className="pc-mono" fontSize="22" letterSpacing="2">
            {p.sets === 1 ? 'SET' : 'SETS'}
          </text>
          <text x="392" y="1278" className="pc-mono" fontSize="22" letterSpacing="2">
            TOTAL LIFTED
          </text>
          <text x="720" y="1278" className="pc-mono" fontSize="22" letterSpacing="2">
            TIME
          </text>
        </g>
      </svg>
    </div>
  )
}

/** The HTML stamp, for places outside a card (waitlist confirmation, 404). */
export function Stamp({ top, big, bottom, animate }: { top: string; big: string; bottom: string; animate?: boolean }) {
  return (
    <div className={`stamp${animate ? ' stamp-animate' : ''}`} aria-hidden="true">
      <span className="stamp-label">{top}</span>
      <span className="stamp-num">{big}</span>
      <span className="stamp-week">{bottom}</span>
    </div>
  )
}

export { proofLabel }
