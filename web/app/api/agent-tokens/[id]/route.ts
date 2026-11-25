import { revokeAgentToken } from '@/lib/server/domain/agentTokens';
import { services } from '@/lib/server/firebase';
import { authenticated } from '@/lib/server/http';

export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return authenticated(request, 'revokeAgentToken.failed', (uid) => revokeAgentToken(services(), uid, { tokenId: id }), { body: false });
}
