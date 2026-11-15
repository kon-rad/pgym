import type { Metadata, Viewport } from 'next'
import type { ReactNode } from 'react'
import { RevealOnScroll } from '@/components/Reveal'
import { SiteFooter, SiteHeader } from '@/components/SiteChrome'
import { site } from '@/lib/site'
import { anton, archivo, jetbrainsMono } from './fonts'
import './globals.css'

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: 'PGYM. Proof of gym.',
    template: '%s · PGYM',
  },
  description: site.description,
  applicationName: 'PGYM',
  openGraph: {
    type: 'website',
    siteName: 'PGYM',
    title: 'PGYM. Proof of gym.',
    description: site.description,
    url: '/',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'PGYM. Proof of gym.',
    description: site.description,
  },
  formatDetection: { email: false, telephone: false, address: false },
}

export const viewport: Viewport = {
  themeColor: '#0B0B0C',
  colorScheme: 'dark',
}

// Marks the page as scripted before first paint, so scroll reveals only hide
// content when JavaScript is there to show it again.
const JS_FLAG = "document.documentElement.classList.add('js')"

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html
      lang="en"
      className={`${anton.variable} ${archivo.variable} ${jetbrainsMono.variable}`}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: JS_FLAG }} />
      </head>
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <SiteHeader />
        <main id="main">{children}</main>
        <SiteFooter />
        <RevealOnScroll />
      </body>
    </html>
  )
}
