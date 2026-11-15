import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { Marked } from 'marked'
import { site } from './site'

// The site's markdown pages live in web/content/, copied unchanged from the
// vault's PGYM site copy (copy/site/). Each file has a small frontmatter block
// (title, description, path; posts add slug, author, date). Placeholders are
// filled from configuration at build time, never by hand:
//
//   [DOMAIN]      host of NEXT_PUBLIC_SITE_URL, when it is set
//   [API-DOMAIN]  host of NEXT_PUBLIC_API_URL, when it is set
//   [EMAIL]       NEXT_PUBLIC_SUPPORT_EMAIL, when it is set
//
// Unset values keep their placeholder, so nothing invented reaches the page.

export const CONTENT_DIR = join(process.cwd(), 'content')

export interface Doc {
  meta: Record<string, string>
  /** Markdown body, frontmatter and HTML comments removed, placeholders filled. */
  body: string
}

/** Splits `---` frontmatter of simple `key: value` lines from the body. */
export function parseFrontmatter(source: string): Doc {
  const text = source.replace(/\r\n/g, '\n')
  const match = /^---\n([\s\S]*?)\n---\n?/.exec(text)
  if (!match) return { meta: {}, body: text }
  const meta: Record<string, string> = {}
  for (const line of match[1].split('\n')) {
    const kv = /^([A-Za-z][\w-]*):\s*(.*)$/.exec(line)
    if (!kv) continue
    let value = kv[2].trim()
    if (/^".*"$/.test(value) || /^'.*'$/.test(value)) value = value.slice(1, -1)
    meta[kv[1]] = value
  }
  return { meta, body: text.slice(match[0].length) }
}

function hostOf(url: string): string | null {
  try {
    const u = new URL(url)
    if (u.hostname === 'localhost' || u.hostname === '127.0.0.1' || u.hostname.includes('[')) return null
    return u.host
  } catch {
    return null
  }
}

export interface Placeholders {
  domain: string | null
  apiDomain: string | null
  email: string | null
  /** [COMPANY] in the legal drafts, from NEXT_PUBLIC_OPERATOR_NAME. */
  company?: string | null
  /** [ADDRESS] in the legal drafts, from NEXT_PUBLIC_OPERATOR_ADDRESS. */
  address?: string | null
}

export function sitePlaceholders(): Placeholders {
  return {
    domain: process.env.NEXT_PUBLIC_SITE_URL ? hostOf(site.url) : null,
    apiDomain: process.env.NEXT_PUBLIC_API_URL ? hostOf(site.apiUrl) : null,
    email: site.supportEmail || null,
    company: site.operator.startsWith('[') ? null : site.operator,
    address: site.address.startsWith('[') ? null : site.address,
  }
}

/** Fills [DOMAIN], [API-DOMAIN], [EMAIL], [COMPANY] and [ADDRESS] where configured; leaves them otherwise. */
export function fillPlaceholders(text: string, values: Placeholders): string {
  let out = text
  if (values.apiDomain) out = out.split('[API-DOMAIN]').join(values.apiDomain)
  if (values.domain) out = out.split('[DOMAIN]').join(values.domain)
  if (values.email) out = out.split('[EMAIL]').join(values.email)
  if (values.company) out = out.split('[COMPANY]').join(values.company)
  if (values.address) out = out.split('[ADDRESS]').join(values.address)
  return out
}

/** Removes HTML comments (vault notes) so they never reach a page or the skill file. */
export function stripComments(text: string): string {
  return text.replace(/<!--[\s\S]*?-->\n?/g, '')
}

/**
 * Drops the first `# Title` line, wherever it is; the page renders the title
 * itself. (The open-source copy has its licence note above the title.)
 */
export function stripTitle(body: string): string {
  return body.replace(/^# [^\n]*\n+/m, '').replace(/^\s+/, '')
}

function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

const marked = new Marked({
  gfm: true,
  async: false,
  renderer: {
    // Raw HTML in the source is shown as text, never rendered, so a stray tag in
    // a copy edit cannot run on the site.
    html(token) {
      return escapeHtml(token.text)
    },
  },
})

/**
 * Markdown to HTML. The input is the site's own committed copy, never user
 * input. Tables are wrapped so a wide one scrolls sideways on a phone.
 */
export function renderMarkdown(markdown: string): string {
  const html = marked.parse(markdown) as string
  return html.replace(/<table>/g, '<div class="table-wrap"><table>').replace(/<\/table>/g, '</table></div>')
}

export function readDoc(file: string, values: Placeholders = sitePlaceholders()): Doc {
  const { meta, body } = parseFrontmatter(readFileSync(join(CONTENT_DIR, file), 'utf8'))
  return { meta, body: fillPlaceholders(stripComments(body), values).trim() + '\n' }
}

/** One `##` section of a document page, for the contents list and the page body. */
export interface Section {
  id: string
  /** The heading as plain text. */
  title: string
  /** The section body as HTML, without its heading. */
  html: string
}

export interface Page {
  title: string
  description: string
  /** The whole body as HTML. */
  html: string
  /** HTML before the first `##` heading. */
  intro: string
  sections: Section[]
  meta: Record<string, string>
}

/** A heading's anchor: lower case, letters and digits, words joined by hyphens. */
export function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[`*_]/g, '')
    .replace(/&[a-z]+;/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

/** Splits a markdown body at its `## ` headings (outside fenced code). */
export function splitSections(markdown: string): { intro: string; sections: Section[] } {
  const lines = markdown.split('\n')
  const chunks: { title: string | null; lines: string[] }[] = [{ title: null, lines: [] }]
  let fenced = false
  for (const line of lines) {
    if (/^(```|~~~)/.test(line)) fenced = !fenced
    const h = !fenced && /^## (.+?)\s*#*\s*$/.exec(line)
    if (h) chunks.push({ title: h[1], lines: [] })
    else chunks[chunks.length - 1].lines.push(line)
  }
  const used = new Map<string, number>()
  const sections = chunks.slice(1).map((c) => {
    const title = c.title!.replace(/[`*_]/g, '')
    let id = slugify(title) || 'section'
    const n = used.get(id) ?? 0
    used.set(id, n + 1)
    if (n > 0) id = `${id}-${n + 1}`
    return { id, title, html: renderMarkdown(c.lines.join('\n')) }
  })
  return { intro: renderMarkdown(chunks[0].lines.join('\n')), sections }
}

export function loadPage(file: string): Page {
  const { meta, body } = readDoc(file)
  const markdown = stripTitle(body)
  return {
    title: meta.title ?? '',
    description: meta.description ?? '',
    html: renderMarkdown(markdown),
    ...splitSections(markdown),
    meta,
  }
}

export interface PostSummary {
  slug: string
  title: string
  description: string
  author: string
  /** "[PUBLISH-DATE]" until the post is published; shown as "Draft". */
  date: string | null
}

export function listPosts(): PostSummary[] {
  return readdirSync(join(CONTENT_DIR, 'blog'))
    .filter((f) => f.endsWith('.md'))
    .map((f) => {
      const { meta } = parseFrontmatter(readFileSync(join(CONTENT_DIR, 'blog', f), 'utf8'))
      const slug = meta.slug || f.replace(/\.md$/, '')
      const date = meta.date && !meta.date.startsWith('[') ? meta.date : null
      return { slug, title: meta.title ?? slug, description: meta.description ?? '', author: meta.author ?? 'PGYM', date }
    })
    .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '') || a.slug.localeCompare(b.slug))
}

export function loadPost(slug: string): Page | null {
  const post = listPosts().find((p) => p.slug === slug)
  if (!post) return null
  return loadPage(join('blog', `${slug}.md`))
}

/** The skill file exactly as an agent should read it: frontmatter kept, comments removed, placeholders filled. */
export function skillFile(values: Placeholders = sitePlaceholders()): string {
  const source = readFileSync(join(CONTENT_DIR, 'skill.md'), 'utf8').replace(/\r\n/g, '\n')
  return fillPlaceholders(stripComments(source), values)
}
