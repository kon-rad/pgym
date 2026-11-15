import type { ReactNode } from 'react'
import type { Page } from '@/lib/content'
import { TocSpy } from './TocSpy'

// The document template from pgym-landing-design.md section 5: one Anton H1, a
// mono label under it, then the text set for reading. Pages with four or more
// sections get a contents list: an Iron box under the H1 on a phone, a sticky
// column on the left from 768 px, with the current section in Chalk.

export const TOC_MIN_SECTIONS = 4

export function DocPage({
  page,
  label,
  boxed = [],
  toc = true,
  children,
}: {
  page: Page
  /** The mono label under the H1, for example "LAST UPDATED 2026-11-15". */
  label?: ReactNode
  /** Section ids set apart in a 1 px Ash outlined box (the photo and AI section on /privacy). */
  boxed?: string[]
  /** Set false for pages that never take a contents list (blog posts). */
  toc?: boolean
  /** Shown under the label: the draft line, a button, the post's byline. */
  children?: ReactNode
}) {
  const withToc = toc && page.sections.length >= TOC_MIN_SECTIONS
  return (
    <div className={`doc${withToc ? ' doc-with-toc' : ''}`}>
      <div className="wrap doc-grid">
        <header className="doc-head">
          <h1 className="doc-title">{page.title}</h1>
          {label ? <p className="label doc-label">{label}</p> : null}
          {children}
        </header>
        {withToc ? (
          <nav className="doc-toc" aria-label="Contents">
            <p className="label">Contents</p>
            <ol>
              {page.sections.map((s) => (
                <li key={s.id}>
                  <a href={`#${s.id}`}>{s.title}</a>
                </li>
              ))}
            </ol>
            <TocSpy ids={page.sections.map((s) => s.id)} />
          </nav>
        ) : null}
        {/* Rendered from the site's own committed markdown; raw HTML in it is escaped. */}
        <div className="doc-body prose">
          {page.intro.trim() ? <div dangerouslySetInnerHTML={{ __html: page.intro }} /> : null}
          {page.sections.map((s) => (
            <section key={s.id} id={s.id} className={boxed.includes(s.id) ? 'doc-box' : undefined} aria-labelledby={`${s.id}-h`}>
              <h2 id={`${s.id}-h`}>{s.title}</h2>
              <div dangerouslySetInnerHTML={{ __html: s.html }} />
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}
