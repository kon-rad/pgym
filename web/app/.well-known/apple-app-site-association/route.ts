import { appleAppSiteAssociation } from '@/lib/aasa'

// Read the environment on every request, so the team ID can be set on the host
// without a rebuild.
export const dynamic = 'force-dynamic'

export function GET(): Response {
  return new Response(JSON.stringify(appleAppSiteAssociation()), {
    status: 200,
    headers: {
      // iOS requires application/json and no redirect.
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  })
}
