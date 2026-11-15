import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import {
  CameraScreen,
  CompleteScreen,
  EditorScreen,
  Phone,
  ProgressScreen,
  ProofWallScreen,
  SessionScreen,
} from '@/components/AppScreens'
import { DocPage } from '@/components/DocPage'
import { LOOP_STEPS } from '@/components/LoopDemo'
import type { ProofCardProps } from '@/components/ProofCard'
import { StreakWeek } from '@/components/StreakWeek'
import { WaitlistForm } from '@/components/WaitlistForm'
import { splitSections } from '@/lib/content'
import { FORM_NOTE, MESSAGES } from '@/lib/waitlist/messages'

// The home page's parts: the app screens in phone frames, the streak row, the
// loop copy, the waitlist form and the document template.

const CARD: ProofCardProps = {
  proof: 42,
  streakWeeks: 7,
  time: 'SUN 15 NOV 2026 · 18:47',
  name: 'Push A',
  sets: 18,
  total: '6,240',
  duration: '1:12',
  filter: 'iron',
}

const html = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el)

describe('app screens', () => {
  const screens = {
    editor: html(createElement(EditorScreen, { card: CARD })),
    session: html(createElement(SessionScreen)),
    camera: html(createElement(CameraScreen)),
    complete: html(createElement(CompleteScreen, { card: CARD })),
    progress: html(createElement(ProgressScreen)),
    wall: html(createElement(ProofWallScreen)),
  }

  it.each(Object.entries(screens))('%s never shows the physique score', (_, markup) => {
    expect(markup.toLowerCase()).not.toMatch(/physique|score/)
  })

  it('the editor shows 4:5 and Iron selected, Retake and Stamp it (view D8)', () => {
    expect(screens.editor).toContain('<span class="on">4:5</span>')
    expect(screens.editor).toContain('<span class="on">iron</span>')
    expect(screens.editor).toContain('Retake')
    expect(screens.editor).toContain('Stamp it')
  })

  it('the camera has a shutter and no photo-library button (view D7)', () => {
    expect(screens.camera).toContain('scr-shutter')
    expect(screens.camera.toLowerCase()).not.toMatch(/library|camera roll|gallery/)
  })

  it('the session ends in Finish and take proof (view D2)', () => {
    expect(screens.session).toContain('Finish and take proof')
    expect(screens.session.match(/ld-check-\d/g)).toEqual(['ld-check-1', 'ld-check-2', 'ld-check-3'])
  })

  it('session complete says the week is locked (view D11)', () => {
    expect(screens.complete).toContain('Week 7 locked.')
    expect(screens.complete).toContain('Share proof')
  })

  it('the proof wall groups by month, newest first (view E2)', () => {
    const nov = screens.wall.indexOf('November 2026')
    const oct = screens.wall.indexOf('October 2026')
    expect(nov).toBeGreaterThan(-1)
    expect(oct).toBeGreaterThan(nov)
    expect(screens.wall.indexOf('#042')).toBeLessThan(screens.wall.indexOf('#025'))
  })

  it('a phone frame is one labelled image with the drawing hidden', () => {
    const frame = html(Phone({ size: 's', desktop: 'm', label: 'A screen', children: 'x' }))
    expect(frame).toContain('class="phone phone-s phone-up-m"')
    expect(frame).toContain('role="img" aria-label="A screen"')
    expect(frame).toContain('aria-hidden="true"')
    expect(frame).toContain('9:41')
  })
})

describe('streak week', () => {
  const markup = html(createElement(StreakWeek))

  it('draws seven day rings, four done, and reads as one sentence', () => {
    expect(markup.match(/class="day-ring/g)).toHaveLength(7)
    expect(markup.match(/class="day-ring done"/g)).toHaveLength(4)
    expect(markup).toContain('4 OF 4')
    expect(markup).toContain('role="img" aria-label="Example week: 4 of 4 sessions this week, 7 weeks running."')
  })

  it('carries the 7 WEEKS RUNNING stamp', () => {
    expect(markup).toContain('7 WEEKS')
    expect(markup).toContain('RUNNING')
  })
})

describe('loop copy', () => {
  it('uses the three step lines and sentences from the landing copy', () => {
    expect(LOOP_STEPS.map((s) => s.title)).toEqual(['Log your sets.', 'Take one photo.', 'Get your proof.'])
    expect(LOOP_STEPS[2].body).toBe(
      'Pick a filter and tap Stamp it. Our server adds the time and your proof number. Share it wherever you already post.',
    )
  })
})

describe('waitlist form', () => {
  const markup = html(createElement(WaitlistForm, { source: 'hero', inputId: 'hero-email' }))

  it('has the copy label, the design placeholder and the fixed message line', () => {
    expect(markup).toContain('<label for="hero-email" class="visually-hidden">Your email</label>')
    expect(markup).toContain('placeholder="you@email.com"')
    expect(markup).toMatch(/<p id="[^"]+-message" class="form-message"><\/p>/)
    expect(markup).toContain(FORM_NOTE)
    expect(markup).toContain('href="/privacy"')
  })

  it('answers with the copy lines and never in guilt or alarm words', () => {
    expect(MESSAGES.joined).toBe('You are on the list. Check your inbox.')
    expect(MESSAGES.invalid).toBe('That does not look like an email address.')
    expect(MESSAGES.unavailable).toBe('Something went wrong on our side. Try again in a minute.')
    for (const m of Object.values(MESSAGES)) expect(m).not.toMatch(/oops|!|error|failed/i)
  })
})

describe('document template', () => {
  const page = {
    title: 'Privacy policy',
    description: '',
    html: '',
    meta: {},
    ...splitSections('Intro.\n\n## One\n\na\n\n## Two\n\nb\n\n## Three\n\nc\n\n## Four\n\nd\n'),
  }

  it('adds a contents list from four sections and boxes the chosen section', () => {
    const markup = html(createElement(DocPage, { page, label: 'Last updated 2026-11-15', boxed: ['two'] }))
    expect(markup).toContain('<nav class="doc-toc" aria-label="Contents">')
    expect(markup).toContain('href="#four"')
    expect(markup).toContain('<section id="two" class="doc-box"')
    expect(markup).toContain('Last updated 2026-11-15')
  })

  it('has no contents list under four sections', () => {
    const short = { ...page, ...splitSections('## One\n\na\n\n## Two\n\nb\n') }
    expect(html(createElement(DocPage, { page: short }))).not.toContain('doc-toc')
  })
})
