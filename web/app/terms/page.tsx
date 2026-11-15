import type { Metadata } from 'next'
import { DocPage } from '@/components/DocPage'
import { DraftNotice } from '@/components/PageHead'
import { loadPage } from '@/lib/content'

// Copy: content/terms.md, Part 1 of the vault's copy/pgym-terms-draft.md.
// It is a draft, not reviewed by a lawyer, and the page says so above the text.
const page = loadPage('terms.md')

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: page.title,
  description: page.description,
  alternates: { canonical: '/terms' },
}

export default function TermsPage() {
  return (
    <DocPage page={page} label={`Last updated ${page.meta.updated}`}>
      <DraftNotice />
    </DocPage>
  )
}
