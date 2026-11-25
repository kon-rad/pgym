import type { Metadata } from 'next'
import { site } from '@/lib/site'

export const metadata: Metadata = {
  title: 'Contact us',
  description: 'Contact Konrad about PGYM by email or on X.',
  alternates: { canonical: '/contact' },
}

export default function ContactPage() {
  return (
    <main className="doc">
      <div className="wrap contact-page">
        <span className="label">PGYM / Contact</span>
        <h1 className="display display-h1">Get in touch<span className="dot">.</span></h1>
        <p className="lead">Questions, feedback, or a problem with PGYM? Reach me directly.</p>
        <div className="contact-links">
          <a href={`mailto:${site.supportEmail}?subject=PGYM`}>Email <strong>{site.supportEmail}</strong></a>
          <a href={site.ownerXUrl}>X <strong>@konrad_gnat</strong></a>
        </div>
      </div>
    </main>
  )
}
