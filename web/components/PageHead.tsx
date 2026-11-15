import type { ReactNode } from 'react'
import { mailto, site } from '@/lib/site'

export function PageHead({ label, title, children }: { label: string; title: string; children?: ReactNode }) {
  return (
    <div className="page-head">
      <span className="label label-plate">{label}</span>
      <h1 className="display display-l">{title}</h1>
      {children}
    </div>
  )
}

export const DRAFT_LINE = 'DRAFT, not reviewed by a lawyer'

/**
 * The first line of both legal drafts (copy/pgym-privacy-policy-draft.md and
 * copy/pgym-terms-draft.md), kept visible on /privacy and /terms until a lawyer
 * has reviewed them.
 */
export function DraftNotice() {
  return (
    <p className="draft-flag" role="note">
      {DRAFT_LINE}
    </p>
  )
}

/** The support address as a link, or a plain placeholder while none is set. */
export function SupportEmail({ subject }: { subject?: string }) {
  const href = mailto(subject)
  if (!href) return <strong>[EMAIL]</strong>
  return <a href={href}>{site.supportEmail}</a>
}
