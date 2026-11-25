import { deleteAccount } from '@/lib/server/domain/handlers';
import { services } from '@/lib/server/firebase';
import { authenticated } from '@/lib/server/http';

export async function DELETE(request: Request) {
  return authenticated(request, 'deleteAccount.failed', (uid) => deleteAccount(services(), uid), { body: false });
}
