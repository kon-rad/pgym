import type { ReactNode } from 'react'
import type { Page } from '@/lib/content'
import { PageHead } from './PageHead'

/** A page whose body is one of the site's markdown files in web/content/. */
export function MarkdownPage({ label, page, children }: { label: string; page: Page; children?: ReactNode }) {
  return (
    <div className="page">
      <div className="wrap">
        <PageHead label={label} title={page.title}>
          {page.description ? <p className="lede">{page.description}</p> : null}
          {children}
        </PageHead>
        {/* Rendered from the site's own committed markdown; raw HTML in it is escaped. */}
        <div className="prose" data-reveal dangerouslySetInnerHTML={{ __html: page.html }} />
      </div>
    </div>
  )
}
