import type { Metadata } from 'next'
import Link from 'next/link'
import { listPosts } from '@/lib/content'

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: 'Blog',
  description: 'Posts from PGYM: why it exists, how the proof card works, and what changes.',
  alternates: { canonical: '/blog' },
}

// pgym-landing-design.md 8: a list of posts, each a mono date label, a 22 px
// Archivo 700 title and one line, 32 px apart, in the 680 px text column.
export default function BlogIndex() {
  const posts = listPosts()
  return (
    <div className="doc">
      <div className="wrap doc-grid">
        <header className="doc-head">
          <h1 className="doc-title">Blog</h1>
        </header>
        <ul className="doc-body post-list">
          {posts.map((post) => (
            <li key={post.slug} data-reveal>
              <Link className="post-row" href={`/blog/${post.slug}`}>
                <span className="label">{post.date ?? 'Draft'}</span>
                <h2>{post.title}</h2>
                <p>{post.description}</p>
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
