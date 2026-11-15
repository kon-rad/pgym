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

/** Shown on the legal pages until they have had a legal review (card W3). */
export function DraftNotice({ updated }: { updated: string }) {
  return (
    <p className="notice">
      Last updated {updated}. This is a plain-language version written before launch. It will be reviewed before
      PGYM is in the App Store, and any change is posted here with a new date.
    </p>
  )
}

/** The support address as a link, or a plain placeholder while none is set. */
export function SupportEmail({ subject }: { subject?: string }) {
  const href = mailto(subject)
  if (!href) return <strong>[EMAIL]</strong>
  return <a href={href}>{site.supportEmail}</a>
}
