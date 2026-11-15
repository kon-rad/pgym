import type { MetadataRoute } from 'next'
import { listPosts } from '@/lib/content'
import { site } from '@/lib/site'

const PUBLIC_PATHS = [
  '/',
  '/guide',
  '/blog',
  '/agents',
  '/open-source',
  '/skill.md',
  '/privacy',
  '/terms',
  '/support',
  '/delete-account',
] as const

export default function sitemap(): MetadataRoute.Sitemap {
  const paths: string[] = [...PUBLIC_PATHS, ...listPosts().map((p) => `/blog/${p.slug}`)]
  return paths.map((path) => ({
    url: `${site.url}${path === '/' ? '' : path}`,
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : 0.5,
  }))
}
