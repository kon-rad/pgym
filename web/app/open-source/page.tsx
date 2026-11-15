import type { Metadata } from 'next'
import { MarkdownPage } from '@/components/MarkdownPage'
import { loadPage } from '@/lib/content'
import { site } from '@/lib/site'

// Copy: content/open-source.md, the page part of the vault's
// copy/site/pgym-open-source.md (everything above its "END OF THE /open-source
// PAGE" marker), unchanged. The repo drafts below that marker are not site copy.
const page = loadPage('open-source.md')

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: page.title,
  description: page.description,
  alternates: { canonical: '/open-source' },
}

export default function OpenSourcePage() {
  return (
    <MarkdownPage label="Open source" page={page}>
      <p className="open-links">
        <a className="btn btn-secondary" href={site.githubUrl}>
          kon-rad/pgym on GitHub
        </a>
      </p>
    </MarkdownPage>
  )
}
