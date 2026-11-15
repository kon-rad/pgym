// Text rules for the proof card, from pgym-proof-card-spec.md ("The stamp" and
// "Text rules"). Pure functions, so the site's example cards follow the same
// rules the app's renderer does, and the tests can check them.
//
// Glyph widths are estimates: the spec leaves Anton's widths open (open question
// 2), so the name fit uses an average advance of 0.44 em, which is what the
// template's "SHOULDERS, TRICEPS" at 112 px across 952 px implies.

export const NAME_MAX_WIDTH = 952
const ANTON_ADVANCE = 0.44
const ANTON_DIGIT_ADVANCE = 0.5
const STAMP_TEXT_WIDTH = 164

/** "#042": the proof number zero-padded to at least three digits. */
export function proofLabel(proof: number): string {
  return `#${String(Math.max(0, Math.floor(proof))).padStart(3, '0')}`
}

/** Line 3 of the stamp. Never mentions a miss: a gap reads "NEW STREAK". */
export function streakLine(weeks: number, proof?: number): string {
  if (proof === 1) return 'FIRST PROOF'
  if (weeks <= 0) return 'NEW STREAK'
  if (weeks === 1) return '1 WEEK RUNNING'
  return `${weeks} WEEKS RUNNING`
}

/** Stamp number size: 56 px, shrinking in 4 px steps to 40 px when it would not fit 164 px. */
export function stampNumberSize(label: string): number {
  let size = 56
  while (label.length * ANTON_DIGIT_ADVANCE * size > STAMP_TEXT_WIDTH && size > 40) size -= 4
  return size
}

export interface NameLayout {
  size: number
  lines: string[]
  /** Baselines of each line, 4:5 card coordinates. */
  baselines: number[]
  /** Baseline of the timestamp above the name. */
  timeBaseline: number
}

const STEPS = [
  { size: 112, pitch: 108 },
  { size: 96, pitch: 92 },
  { size: 80, pitch: 77 },
] as const

const LAST_BASELINE = 1124

function maxChars(size: number): number {
  return Math.floor(NAME_MAX_WIDTH / (ANTON_ADVANCE * size))
}

function wrap(words: string[], max: number): string[] {
  const lines: string[] = []
  let line = ''
  for (const word of words) {
    const next = line ? `${line} ${word}` : word
    if (line && next.length > max) {
      lines.push(line)
      line = word
    } else {
      line = next
    }
  }
  if (line) lines.push(line)
  return lines
}

function cutToFit(text: string, max: number): string {
  if (text.length <= max) return text
  const words = text.split(' ')
  let kept = ''
  for (const word of words) {
    const next = kept ? `${kept} ${word}` : word
    if (next.length + 1 > max) break
    kept = next
  }
  if (!kept) kept = text.slice(0, max - 1)
  return `${kept}…`
}

function place(size: number, pitch: number, lines: string[]): NameLayout {
  const baselines = lines.length === 2 ? [LAST_BASELINE - pitch, LAST_BASELINE] : [LAST_BASELINE]
  return { size, lines, baselines, timeBaseline: baselines[0] - size - 24 }
}

/**
 * The session name: upper case, at most two lines, bottom-anchored. 112 px,
 * then 96, then 80, then line 2 is cut at the last whole word with an ellipsis.
 * Empty after trimming: "SESSION".
 */
export function layoutName(name: string): NameLayout {
  const text = name.trim().replace(/\s+/g, ' ').toUpperCase() || 'SESSION'
  const words = text.split(' ')
  for (const { size, pitch } of STEPS) {
    const max = maxChars(size)
    const lines = wrap(words, max)
    if (lines.length <= 2 && lines.every((l) => l.length <= max)) return place(size, pitch, lines)
  }
  const { size, pitch } = STEPS[2]
  const max = maxChars(size)
  const lines = wrap(words, max)
  const first = cutToFit(lines[0], max)
  const rest = lines.slice(1).join(' ')
  return place(size, pitch, rest ? [first, cutToFit(rest, max)] : [first])
}
