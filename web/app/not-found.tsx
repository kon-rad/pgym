import type { Metadata } from 'next'
import Link from 'next/link'
import { Stamp } from '@/components/ProofCard'

export const metadata: Metadata = {
  title: 'Page not found',
  robots: { index: false, follow: true },
}

// pgym-landing-design.md 8, "/404": H1 "NO PROOF HERE." on one line, 44 px on a
// phone and 72 px centred on desktop, and a text link home.
export default function NotFound() {
  return (
    <div className="center-page">
      <div className="wrap not-found">
        <Stamp top="PROOF" big="#404" bottom="NOT FOUND" animate />
        <h1 className="display display-h2">No proof here.</h1>
        <Link className="arrow-link" href="/">
          Back to PGYM
        </Link>
      </div>
    </div>
  )
}
