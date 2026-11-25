import { FieldValue } from 'firebase-admin/firestore';
import { services } from '@/lib/server/firebase';
import { authenticated } from '@/lib/server/http';

export async function DELETE(request: Request) {
  return authenticated(request, 'physiqueScores.deleteFailed', async (uid) => {
    const db = services().db;
    const sessions = await db.collection(`users/${uid}/sessions`).get();
    let deleted = 0;
    for (let offset = 0; offset < sessions.size; offset += 400) {
      const batch = db.batch();
      let count = 0;
      for (const session of sessions.docs.slice(offset, offset + 400)) {
        if (session.get('physique') !== undefined) {
          batch.update(session.ref, { physique: FieldValue.delete() });
          count += 1;
        }
      }
      if (count) { await batch.commit(); deleted += count; }
    }
    return { deleted };
  }, { body: false });
}
