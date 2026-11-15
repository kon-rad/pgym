import type { Metadata } from 'next'
import Link from 'next/link'
import { PageHead } from '@/components/PageHead'
import { listPosts } from '@/lib/content'

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: 'Blog',
  description: 'Posts from PGYM: why it exists, how the proof card works, and what changes.',
  alternates: { canonical: '/blog' },
}

export default function BlogIndex() {
  const posts = listPosts()
  return (
    <div className="page">
      <div className="wrap">
        <PageHead label="Blog" title="Blog" />
        <ul className="post-list">
          {posts.map((post) => (
            <li key={post.slug} data-reveal>
              <Link className="post-card" href={`/blog/${post.slug}`}>
                <span className="label label-plate">{post.date ?? 'Draft'}</span>
                <h2>{post.title}</h2>
                <p>{post.description}</p>
                <span className="arrow-link">Read</span>
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
