import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import { LoopDemo } from '@/components/LoopDemo'
import { Lockup } from '@/components/Logo'
import { ProofCard, type ProofCardProps } from '@/components/ProofCard'
import { layoutName, proofLabel, stampNumberSize, streakLine } from '@/lib/proof-card'

// The proof card follows pgym-proof-card-spec.md and the 4:5 template
// (pgym-card-4x5.svg). These check the text rules and the drawn card.

const TEMPLATE: ProofCardProps = {
  proof: 42,
  streakWeeks: 7,
  time: 'SUN 15 NOV 2026 · 18:47',
  name: 'Push A: Chest, Shoulders, Triceps',
  sets: 18,
  total: '6,240',
  duration: '1:12',
}

describe('proof number and stamp text', () => {
  it('pads the proof number to at least three digits', () => {
    expect(proofLabel(1)).toBe('#001')
    expect(proofLabel(42)).toBe('#042')
    expect(proofLabel(999)).toBe('#999')
    expect(proofLabel(1000)).toBe('#1000')
    expect(proofLabel(10000)).toBe('#10000')
  })

  it('writes the streak line from the spec, and never mentions a miss', () => {
    expect(streakLine(7, 42)).toBe('7 WEEKS RUNNING')
    expect(streakLine(1, 15)).toBe('1 WEEK RUNNING')
    expect(streakLine(0, 16)).toBe('NEW STREAK')
    expect(streakLine(0, 1)).toBe('FIRST PROOF')
    for (const w of [0, 1, 2, 99]) expect(streakLine(w)).not.toMatch(/MISS|BROKE|LOST/)
  })

  it('keeps the stamp number at 56 px until it needs to shrink, never below 40', () => {
    expect(stampNumberSize('#042')).toBe(56)
    expect(stampNumberSize('#10000')).toBeLessThan(56)
    expect(stampNumberSize('#1000000000')).toBe(40)
  })
})

describe('session name layout', () => {
  it('lays out the template name on two lines at 112 px with the template baselines', () => {
    const name = layoutName(TEMPLATE.name)
    expect(name.size).toBe(112)
    expect(name.lines).toEqual(['PUSH A: CHEST,', 'SHOULDERS, TRICEPS'])
    expect(name.baselines).toEqual([1016, 1124])
    expect(name.timeBaseline).toBe(880)
  })

  it('puts a one-line name on the last baseline and the timestamp at 988', () => {
    const name = layoutName('Legs')
    expect(name.lines).toEqual(['LEGS'])
    expect(name.baselines).toEqual([1124])
    expect(name.timeBaseline).toBe(988)
  })

  it('reads SESSION when the name is empty', () => {
    expect(layoutName('   ').lines).toEqual(['SESSION'])
  })

  it('shrinks a long name, then cuts line 2 at a whole word with an ellipsis', () => {
    const shrunk = layoutName('Upper body strength and conditioning day')
    expect(shrunk.size).toBeLessThan(112)
    expect(shrunk.lines.length).toBeLessThanOrEqual(2)

    const cut = layoutName('Push pull legs upper lower full body arms shoulders core cardio mobility')
    expect(cut.size).toBe(80)
    expect(cut.lines).toHaveLength(2)
    expect(cut.lines[1].endsWith('…')).toBe(true)
    expect(cut.baselines).toEqual([1047, 1124])
    expect(cut.timeBaseline).toBe(943)
  })
})

describe('ProofCard', () => {
  const html = renderToStaticMarkup(createElement(ProofCard, TEMPLATE))

  it('draws the template at 1080 x 1350 with the scrim over the lower 55%', () => {
    expect(html).toContain('viewBox="0 0 1080 1350"')
    expect(html).toContain('y="608" width="1080" height="742"')
    expect(html).toContain('fill-opacity="0.75"')
  })

  it('has the stamp: rotated 4 degrees anticlockwise, PROOF, the number and the streak line', () => {
    expect(html).toContain('rotate(-4 882 118)')
    expect(html).toContain('>PROOF<')
    expect(html).toContain('>#042<')
    expect(html).toContain('>7 WEEKS RUNNING<')
  })

  it('has the timestamp, the name and the stat row', () => {
    expect(html).toContain('SUN 15 NOV 2026 · 18:47')
    expect(html).toContain('>SHOULDERS, TRICEPS<')
    expect(html).toContain('>18<')
    expect(html).toMatch(/6,240<tspan[^>]*>KG<\/tspan>/)
    expect(html).toContain('>1:12<')
    expect(html).toContain('>SETS<')
    expect(html).toContain('>TOTAL LIFTED<')
    expect(html).toContain('>TIME<')
  })

  it('is one labelled image for screen readers', () => {
    expect(html).toContain('role="img"')
    expect(html).toMatch(/aria-label="Example proof card #042: Push A/)
  })

  it('never carries a physique score', () => {
    expect(html).not.toMatch(/score|physique/i)
  })

  it('applies a filter to the photo only, and none for Raw', () => {
    const iron = renderToStaticMarkup(createElement(ProofCard, { ...TEMPLATE, filter: 'iron' }))
    expect(iron).toContain('<filter')
    expect(iron).toContain('mode="soft-light"')
    const raw = renderToStaticMarkup(createElement(ProofCard, { ...TEMPLATE, filter: 'raw' }))
    expect(raw).not.toContain('<filter')
  })

  it('gives every card its own filter ids, so cards on one page do not share them', () => {
    const page = renderToStaticMarkup(
      createElement('div', null, createElement(ProofCard, TEMPLATE), createElement(ProofCard, TEMPLATE)),
    )
    const ids = [...page.matchAll(/<filter id="([^"]+)"/g)].map((m) => m[1])
    expect(ids).toHaveLength(2)
    expect(new Set(ids).size).toBe(2)
  })

  it('marks the stamp to land only when asked', () => {
    expect(html).not.toContain('pc-stamp-animate')
    const animated = renderToStaticMarkup(createElement(ProofCard, { ...TEMPLATE, animateStamp: true }))
    expect(animated).toContain('pc-stamp-animate')
  })
})

describe('LoopDemo', () => {
  const html = renderToStaticMarkup(createElement(LoopDemo, { card: TEMPLATE }))

  it('has the three screens and the three steps in order', () => {
    const order = ['ld-frame-log', 'ld-frame-photo', 'ld-frame-card'].map((c) => html.indexOf(c))
    expect(order.every((i) => i >= 0)).toBe(true)
    expect([...order].sort((a, b) => a - b)).toEqual(order)
    const steps = ['Log your sets', 'Take one photo', 'Get your proof'].map((t) => html.indexOf(t))
    expect(steps.every((i) => i >= 0)).toBe(true)
    expect([...steps].sort((a, b) => a - b)).toEqual(steps)
  })

  it('describes the animation once and hides the drawing from screen readers', () => {
    expect(html).toMatch(/role="img" aria-label="An animation of the loop/)
    expect(html).toContain('aria-hidden="true"')
  })
})

describe('Lockup', () => {
  it('uses the mono cut below a 48 px mark box and the master above it', () => {
    expect(renderToStaticMarkup(createElement(Lockup, { height: 26 }))).toContain('data-cut="mono"')
    expect(renderToStaticMarkup(createElement(Lockup, { height: 60 }))).toContain('data-cut="master"')
  })
})
