import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from '@/lib/server/errors';
import { failure, ok, uidFromRequest } from '@/lib/server/http';
import { services } from '@/lib/server/firebase';
import { requireProEntitlement } from '@/lib/server/revenuecat';
import { MAX_PHYSIQUE_JPEG_BYTES, PHYSIQUE_PROMPT_VERSION, scoreJpeg, TogetherPhysiqueProvider } from '@/lib/server/physique';

export async function POST(request: Request) {
  try {
    const uid = await uidFromRequest(request);
    await requireProEntitlement(uid);
    const sessionId = new URL(request.url).searchParams.get('sessionId');
    if (!sessionId || !/^[A-Za-z0-9_-]{1,128}$/.test(sessionId)) throw new HttpsError('invalid-argument', 'A session is required.');
    if (request.headers.get('content-type')?.split(';')[0] !== 'image/jpeg') throw new HttpsError('invalid-argument', 'A JPEG is required.');
    if (Number(request.headers.get('content-length') || 0) > MAX_PHYSIQUE_JPEG_BYTES) throw new HttpsError('invalid-argument', 'The JPEG is too large.');
    const db = services().db;
    const user = await db.doc(`users/${uid}`).get();
    const session = await db.doc(`users/${uid}/sessions/${sessionId}`).get();
    const birthYear = user.get('birthYear');
    if (user.get('physiqueConsent') !== true || typeof birthYear !== 'number' || new Date().getUTCFullYear() - birthYear <= 18) {
      throw new HttpsError('permission-denied', 'Adult photo-analysis consent is required.');
    }
    if (session.get('status') !== 'stamped') throw new HttpsError('failed-precondition', 'Stamp the proof first.');
    const jpeg = new Uint8Array(await request.arrayBuffer());
    if (jpeg.byteLength > MAX_PHYSIQUE_JPEG_BYTES) throw new HttpsError('invalid-argument', 'The JPEG is too large.');
    const now = new Date();
    const rateRef = db.doc(`users/${uid}/privateRateLimits/physique-${now.toISOString().slice(0, 10)}`);
    await db.runTransaction(async (tx) => {
      const previous = await tx.get(rateRef);
      const count = previous.get('count') || 0;
      if (count >= 3) throw new HttpsError('resource-exhausted', 'Try again tomorrow.');
      tx.set(rateRef, { count: count + 1, updatedAt: Timestamp.fromDate(now) });
    });
    const result = await scoreJpeg(new TogetherPhysiqueProvider(process.env.TOGETHER_API_KEY || ''), jpeg);
    await session.ref.update({ physique: { ...result, analyzedAt: Timestamp.fromDate(now), modelVersion: PHYSIQUE_PROMPT_VERSION } });
    return ok(result);
  } catch (error) {
    return failure(error, 'physiqueScore.failed');
  }
}
