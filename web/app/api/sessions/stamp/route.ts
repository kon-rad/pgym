import { stampSession } from '@/lib/server/domain/handlers';
import { services } from '@/lib/server/firebase';
import { authenticated } from '@/lib/server/http';
import { enforceRateLimit } from '@/lib/server/rate-limit';

export async function POST(request: Request) {
  return authenticated(request, 'stampSession.failed', async (uid, body) => {
    enforceRateLimit(`stamp:${uid}`, 20, 60_000);
    return stampSession(services(), uid, body);
  });
}
