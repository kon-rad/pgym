import type { ReactNode } from 'react'
import type { Page } from '@/lib/content'
import { DocPage } from './DocPage'

/**
 * A page whose body is one of the site's markdown files in web/content/, in the
 * document template. The description sits under the H1 as the lead.
 */
export function MarkdownPage({
  label,
  page,
  toc = true,
  children,
}: {
  label?: ReactNode
  page: Page
  toc?: boolean
  children?: ReactNode
}) {
  return (
    <DocPage page={page} label={label} toc={toc}>
      {page.description ? <p className="lede doc-lede">{page.description}</p> : null}
      {children}
    </DocPage>
  )
}
