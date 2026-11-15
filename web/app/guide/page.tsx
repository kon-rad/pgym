import type { Metadata } from 'next'
import { MarkdownPage } from '@/components/MarkdownPage'
import { loadPage } from '@/lib/content'

// Copy: content/guide.md, from the vault's copy/site/pgym-guide.md, unchanged.
const page = loadPage('guide.md')

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: page.title,
  description: page.description,
  alternates: { canonical: '/guide' },
}

export default function GuidePage() {
  return <MarkdownPage label="Guide" page={page} />
}
