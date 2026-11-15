import type { Metadata } from 'next'
import Link from 'next/link'
import { Stamp } from '@/components/ProofCard'

export const metadata: Metadata = {
  title: 'Page not found',
  robots: { index: false, follow: true },
}

export default function NotFound() {
  return (
    <div className="center-page">
      <div className="wrap center-grid">
        <div className="hero-copy">
          <span className="label label-plate">404</span>
          <h1 className="display display-l">No proof of this page.</h1>
          <p className="lede">The link may be old, or the address has a typo. The rest of the site is still here.</p>
          <Link className="btn btn-primary" href="/">
            Back to PGYM
          </Link>
        </div>
        <div className="hero-visual">
          <div style={{ transform: 'scale(2.2)', padding: 40 }}>
            <Stamp top="PROOF" big="#404" bottom="NOT FOUND" animate />
          </div>
        </div>
      </div>
    </div>
  )
}
