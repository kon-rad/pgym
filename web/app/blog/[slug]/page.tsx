import type { Metadata } from 'next'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { MarkdownPage } from '@/components/MarkdownPage'
import { listPosts, loadPost } from '@/lib/content'

// Posts are markdown files in content/blog/. Only those slugs exist; any other
// path is a 404.

export const dynamicParams = false

export function generateStaticParams() {
  return listPosts().map((p) => ({ slug: p.slug }))
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params
  const page = loadPost(slug)
  if (!page) return {}
  return {
    title: page.title,
    description: page.description,
    alternates: { canonical: `/blog/${slug}` },
    openGraph: { type: 'article', title: page.title, description: page.description },
  }
}

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params
  const page = loadPost(slug)
  if (!page) notFound()
  const date = page.meta.date && !page.meta.date.startsWith('[') ? page.meta.date : 'Draft'
  return (
    <MarkdownPage label={`${date} · By ${page.meta.author || 'PGYM'}`} page={page} toc={false}>
      <p className="page-meta">
        <Link className="arrow-link" href="/blog">
          All posts
        </Link>
      </p>
    </MarkdownPage>
  )
}
