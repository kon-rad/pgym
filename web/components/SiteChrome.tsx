import Link from 'next/link'
import { mailto, site } from '@/lib/site'
import { HeaderAction } from './CallToAction'
import { Lockup } from './Logo'

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="wrap">
        <Link href="/" className="home-link" aria-label="PGYM home">
          <Lockup height={26} label={false} />
        </Link>
        <HeaderAction />
      </div>
    </header>
  )
}

export function SiteFooter() {
  const mail = mailto()
  const year = new Date().getFullYear()
  return (
    <footer className="site-footer">
      <div className="wrap">
        <div className="footer-grid">
          <div>
            <Lockup height={22} />
            <p className="footer-line">Proof of gym. An iPhone app.</p>
          </div>
          <nav aria-label="Footer">
            <ul className="footer-links">
              <li>
                <a href={site.githubUrl}>GitHub</a>
              </li>
              <li>
                <Link href="/privacy">Privacy</Link>
              </li>
              <li>
                <Link href="/terms">Terms</Link>
              </li>
              <li>
                <Link href="/support">Support</Link>
              </li>
              <li>
                <Link href="/delete-account">Delete your account</Link>
              </li>
              {mail && (
                <li>
                  <a href={mail}>{site.supportEmail}</a>
                </li>
              )}
            </ul>
          </nav>
        </div>
        <p className="footer-line">
          © {year} {site.operator}. The code is open source on GitHub.
        </p>
      </div>
    </footer>
  )
}
