import { createAgentToken } from '@/lib/server/domain/agentTokens';
import { services } from '@/lib/server/firebase';
import { authenticated } from '@/lib/server/http';
import { enforceRateLimit } from '@/lib/server/rate-limit';
import { requireProEntitlement } from '@/lib/server/revenuecat';

export async function POST(request: Request) {
  return authenticated(request, 'createAgentToken.failed', async (uid, body) => {
    await requireProEntitlement(uid);
    enforceRateLimit(`token:${uid}`, 10, 60_000);
    return createAgentToken(services(), uid, body);
  }, { status: 201 });
}
