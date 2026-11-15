import type { Metadata } from 'next'
import { DocPage } from '@/components/DocPage'
import { DraftNotice } from '@/components/PageHead'
import { loadPage } from '@/lib/content'

// Copy: content/privacy.md, Part 1 of the vault's copy/pgym-privacy-policy-draft.md.
// It is a draft, not reviewed by a lawyer, and the page says so above the text.
const page = loadPage('privacy.md')

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: page.title,
  description: page.description,
  alternates: { canonical: '/privacy' },
}

// pgym-landing-design.md 5: the photo and AI analysis section sits in a 1 px Ash box.
const PHOTO_SECTION = 'the-physique-score-and-google-s-gemini'

export default function PrivacyPage() {
  return (
    <DocPage page={page} label={`Last updated ${page.meta.updated}`} boxed={[PHOTO_SECTION]}>
      <DraftNotice />
    </DocPage>
  )
}
