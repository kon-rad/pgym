import Link from 'next/link'
import { site } from '@/lib/site'
import { HeaderAction } from './CallToAction'
import { Lockup } from './Logo'
import { SupportEmail } from './PageHead'

// Nav and footer, pgym-landing-design.md 2.1 and 2.11.
//
// The lockup is 128 px wide on a phone (the logo spec's 24 px cap-height
// minimum, so the mono cut of the mark) and 152 px wide from 768 px (the mark
// box passes 48 px there, so the master mark). Two drawings, one shown per width.

export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="wrap">
        <Link href="/" className="home-link" aria-label="PGYM home">
          <span className="lockup-s">
            <Lockup height={37} label={false} />
          </span>
          <span className="lockup-l">
            <Lockup height={44} label={false} />
          </span>
        </Link>
        <HeaderAction />
      </div>
    </header>
  )
}

// pgym-landing-pages.md, home section 11, and pgym-landing-copy.md section 11:
// Guide, Blog, Agents, GitHub, Privacy, Terms, Support. The skill file, the
// open-source page and account deletion are linked here too, so every page is
// one tap from any other.
export const FOOTER_COLUMNS: { title: string; links: [href: string, text: string][] }[] = [
  {
    title: 'PGYM',
    links: [
      ['/guide', 'Guide'],
      ['/blog', 'Blog'],
      ['/agents', 'Agents'],
      ['/skill.md', 'skill.md'],
      ['/open-source', 'Open source'],
      ['/contact', 'Contact us'],
      [site.githubUrl, 'GitHub'],
    ],
  },
  {
    title: 'Legal',
    links: [
      ['/privacy', 'Privacy'],
      ['/terms', 'Terms'],
      ['/support', 'Support'],
      ['/delete-account', 'Delete account'],
    ],
  },
]

export const FOOTER_LINKS = FOOTER_COLUMNS.flatMap((c) => c.links)

export function SiteFooter() {
  const year = new Date().getFullYear()
  return (
    <footer className="site-footer">
      <div className="wrap">
        <div className="footer-grid">
          <Link href="/" className="footer-lockup" aria-label="PGYM home">
            <Lockup height={37} label={false} />
          </Link>
          {FOOTER_COLUMNS.map((col) => (
            <nav className="footer-col" aria-label={col.title} key={col.title}>
              <p className="label">{col.title}</p>
              <ul>
                {col.links.map(([href, text]) => (
                  <li key={href}>
                    {href.startsWith('/') && !href.endsWith('.md') ? (
                      <Link href={href}>{text}</Link>
                    ) : (
                      <a href={href}>{text}</a>
                    )}
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <div className="footer-base">
          <p className="footer-copy">
            © {year} {site.operator}
          </p>
          <p className="footer-mail">
            <SupportEmail />
          </p>
          <p className="footer-made">Made with intention by <a href={site.ownerXUrl}>Konrad Gnat</a></p>
        </div>
      </div>
    </footer>
  )
}
