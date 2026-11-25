import { deleteSession } from '@/lib/server/domain/handlers';
import { services } from '@/lib/server/firebase';
import { authenticated } from '@/lib/server/http';

export async function DELETE(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return authenticated(request, 'deleteSession.failed', (uid) => deleteSession(services(), uid, { sessionId: id }), { body: false });
}
