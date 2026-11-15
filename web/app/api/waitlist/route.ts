import { getWaitlistDeps } from '@/lib/waitlist/deps'
import { handleWaitlist } from '@/lib/waitlist/handler'

export const runtime = 'nodejs'

export async function POST(req: Request): Promise<Response> {
  return handleWaitlist(req, getWaitlistDeps())
}
