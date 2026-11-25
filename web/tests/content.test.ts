import { describe, expect, it } from 'vitest'
import {
  fillPlaceholders,
  listPosts,
  loadPage,
  parseFrontmatter,
  readDoc,
  renderMarkdown,
  skillFile,
  slugify,
  splitSections,
  stripComments,
  stripTitle,
} from '@/lib/content'

// The markdown pages (guide, blog, agents, open source) and /skill.md come from
// web/content/, copied unchanged from the vault's PGYM site copy.

const NONE = { domain: null, apiDomain: null, email: null }

describe('frontmatter and placeholders', () => {
  it('reads quoted and unquoted frontmatter values', () => {
    const { meta, body } = parseFrontmatter('---\ntitle: "For your agent"\npath: /agents\n---\n\n# Hi\n')
    expect(meta).toEqual({ title: 'For your agent', path: '/agents' })
    expect(body.trim()).toBe('# Hi')
  })

  it('leaves placeholders alone when nothing is configured', () => {
    const text = 'https://[DOMAIN]/skill.md and https://[API-DOMAIN]/v1 and [EMAIL]'
    expect(fillPlaceholders(text, NONE)).toBe(text)
  })

  it('fills each placeholder from configuration, API domain first', () => {
    const out = fillPlaceholders('https://[DOMAIN]/x https://[API-DOMAIN]/v1 [EMAIL]', {
      domain: 'pgym.test',
      apiDomain: 'api.pgym.test',
      email: 'help@pgym.test',
    })
    expect(out).toBe('https://pgym.test/x https://api.pgym.test/v1 help@pgym.test')
  })

  it('strips HTML comments and the leading title', () => {
    expect(stripComments('a\n<!-- vault note -->\nb')).toBe('a\nb')
    expect(stripTitle('# Title\n\nBody')).toBe('Body')
    expect(stripTitle('> Note\n\n# Title\n\nBody\n\n## Section')).toBe('> Note\n\nBody\n\n## Section')
  })
})

describe('markdown rendering', () => {
  it('renders tables in a scroll wrapper', () => {
    const html = renderMarkdown('| a | b |\n|---|---|\n| 1 | 2 |\n')
    expect(html).toContain('<div class="table-wrap"><table>')
  })

  it('shows raw HTML as text instead of rendering it', () => {
    const html = renderMarkdown('<script>alert(1)</script>\n\nok')
    expect(html).not.toContain('<script>')
    expect(html).toContain('&lt;script&gt;')
  })

  it('keeps angle brackets inside inline code readable', () => {
    expect(renderMarkdown('`Bearer <your token>`')).toContain('Bearer &lt;your token&gt;')
  })
})

describe('site pages', () => {
  it.each([
    ['guide.md', 'How to use PGYM', 'Set a goal'],
    ['agents.md', 'For your agent', 'Revoke a token'],
    ['open-source.md', 'Open source', 'Report a security problem'],
  ])('%s has its title, description and body', (file, title, heading) => {
    const page = loadPage(file)
    expect(page.title).toBe(title)
    expect(page.description.length).toBeGreaterThan(20)
    expect(page.html).toContain(heading)
    expect(page.html).not.toContain(`<h1>`)
    expect(page.html).not.toContain('<!--')
  })

  it('carries only the page part of the open-source copy, not the repo drafts', () => {
    const { body } = readDoc('open-source.md', NONE)
    expect(body).not.toContain('Repo drafts')
    expect(body).not.toContain('Draft: README.md')
  })

  it('lists the first blog post, unpublished posts read as drafts', () => {
    const posts = listPosts()
    const post = posts.find((p) => p.slug === 'why-proof-of-gym')
    expect(post).toMatchObject({ title: 'Why proof of gym', author: 'PGYM', date: null })
  })
})

describe('document sections', () => {
  it('splits at ## headings, not inside fenced code, with unique anchors', () => {
    const { intro, sections } = splitSections(
      'Intro line.\n\n## What we collect\n\nA\n\n```md\n## not a heading\n```\n\n## What we collect\n\nB\n',
    )
    expect(intro).toContain('Intro line.')
    expect(sections.map((s) => s.id)).toEqual(['what-we-collect', 'what-we-collect-2'])
    expect(sections[0].html).toContain('## not a heading')
  })

  it('makes anchors from headings', () => {
    expect(slugify("The physique score and Google's Gemini")).toBe('the-physique-score-and-google-s-gemini')
    expect(slugify('1. What PGYM is')).toBe('1-what-pgym-is')
  })
})

describe('legal drafts', () => {
  it.each([
    ['privacy.md', 'Privacy policy', ['What we collect', 'Photos and optional AI insight', 'Retention and deletion', 'Children and medical use']],
    ['terms.md', 'Terms of use', ['1. What PGYM is', '6. No medical advice', '7. The physique score is an AI estimate', '8. What a proof number means', '15. Contact']],
  ])('%s carries the draft text in sections', (file, title, headings) => {
    const page = loadPage(file)
    expect(page.title).toBe(title)
    expect(page.meta.updated).toMatch(/^2026-11-(15|25)$/)
    const titles = page.sections.map((s) => s.title)
    for (const h of headings) expect(titles).toContain(h)
    expect(page.html).not.toContain('[[')
    expect(page.html).not.toContain('<!--')
  })

  it('keeps unfilled placeholders visible instead of inventing values', () => {
    const { body } = readDoc('privacy.md', NONE)
    expect(body).toContain('[COMPANY]')
    expect(body).toContain('[ADDRESS]')
    expect(body).toContain('[EMAIL]')
    expect(fillPlaceholders('[COMPANY], [ADDRESS]', { ...NONE, company: 'Example Ltd', address: '1 Main St' })).toBe(
      'Example Ltd, 1 Main St',
    )
  })

  it('names the confirmed MIT licence, and no content file calls it proposed', () => {
    expect(readDoc('terms.md', NONE).body).toContain('The licence is MIT.')
    for (const file of ['agents.md', 'guide.md', 'open-source.md', 'privacy.md', 'skill.md', 'terms.md', 'blog/why-proof-of-gym.md']) {
      const { body } = readDoc(file, NONE)
      expect(body, file).not.toMatch(/MIT[^.\n]*proposed|proposed[^.\n]*MIT|not yet confirmed/i)
    }
  })
})

describe('skill.md', () => {
  const text = skillFile(NONE)

  it('starts with the skill frontmatter an agent loads', () => {
    expect(text.startsWith('---\nname: pgym\ndescription: ')).toBe(true)
  })

  it('has no vault comments and keeps the placeholders when none are configured', () => {
    expect(text).not.toContain('<!--')
    expect(text).not.toContain('[[')
    expect(text).toContain('https://[API-DOMAIN]/v1')
  })

  it('has the six endpoints and the rules', () => {
    for (const path of ['/v1/me', '/v1/stats', '/v1/sessions', '/v1/sessions/{id}', '/v1/exercises/{id}/history', '/v1/sessions/{id}/card']) {
      expect(text).toContain(path)
    }
    expect(text).toContain('## Rules')
  })
})
