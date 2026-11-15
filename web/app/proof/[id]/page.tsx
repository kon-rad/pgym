import type { Metadata } from 'next'
import { CallToAction } from '@/components/CallToAction'
import { ProofCard } from '@/components/ProofCard'

// Reserved for v1.1: a public page for one proof a user chose to publish
// (pgym-landing-pages.md, "The shared proof page"). The route exists now so the
// URL shape and the universal link (/proof/*) do not change later. Until then
// every id gets the same "coming soon" page, and nothing about the id is looked
// up or echoed back.

export const metadata: Metadata = {
  title: 'Shared proofs are coming',
  description: 'Shared proof pages open here soon. Until then, PGYM cards travel as images.',
  robots: { index: false, follow: true },
}

export default function ProofPage() {
  return (
    <div className="center-page">
      <div className="wrap center-grid">
        <div className="hero-copy">
          <span className="label label-plate">Coming soon</span>
          <h1 className="display display-l">Shared proofs open here soon.</h1>
          <p className="lede">
            When someone shares a PGYM card as a link, it will show up on this page. For now cards travel as images,
            straight from the app.
          </p>
          <CallToAction source="proof" />
        </div>
        <div className="hero-visual">
          <ProofCard
            proof={1}
            week={1}
            time="YOUR FIRST SESSION"
            name="Day one"
            sets={1}
            kg="0"
            duration="00:00"
            filter="iron"
            scene={3}
            animateStamp
            label="An example proof card, number 1."
          />
        </div>
      </div>
    </div>
  )
}
