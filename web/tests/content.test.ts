import { describe, expect, it } from 'vitest'
import {
  fillPlaceholders,
  listPosts,
  loadPage,
  parseFrontmatter,
  readDoc,
  renderMarkdown,
  skillFile,
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
