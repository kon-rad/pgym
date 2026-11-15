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

// pgym-landing-pages.md, home section 11: Guide, Blog, Agents, GitHub, Privacy,
// Terms, Support, contact email. Open source, the skill file and account
// deletion are linked here too, so every page is one tap from any other.
export const FOOTER_LINKS: [href: string, text: string][] = [
  ['/guide', 'Guide'],
  ['/blog', 'Blog'],
  ['/agents', 'Agents'],
  ['/skill.md', 'skill.md'],
  ['/open-source', 'Open source'],
  [site.githubUrl, 'GitHub'],
  ['/privacy', 'Privacy'],
  ['/terms', 'Terms'],
  ['/support', 'Support'],
  ['/delete-account', 'Delete your account'],
]

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
              {FOOTER_LINKS.map(([href, text]) => (
                <li key={href}>
                  {href.startsWith('/') && !href.endsWith('.md') ? (
                    <Link href={href}>{text}</Link>
                  ) : (
                    <a href={href}>{text}</a>
                  )}
                </li>
              ))}
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
