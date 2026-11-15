import type { MetadataRoute } from 'next'
import { site } from '@/lib/site'

const PUBLIC_PATHS = ['/', '/privacy', '/terms', '/support', '/delete-account'] as const

export default function sitemap(): MetadataRoute.Sitemap {
  return PUBLIC_PATHS.map((path) => ({
    url: `${site.url}${path === '/' ? '' : path}`,
    changeFrequency: path === '/' ? 'weekly' : 'monthly',
    priority: path === '/' ? 1 : 0.5,
  }))
}
