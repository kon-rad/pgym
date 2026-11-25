import { HttpsError } from '@/lib/server/errors';
import { uidFromRequest, failure, ok } from '@/lib/server/http';
import { log } from '@/lib/server/log';
import { enforceRateLimit } from '@/lib/server/rate-limit';
import { analyzeJpeg, MAX_JPEG_BYTES, TogetherVisionProvider } from '@/lib/server/vision';
import { services } from '@/lib/server/firebase';

export async function POST(request: Request) {
  try {
    const uid = await uidFromRequest(request);
    enforceRateLimit(`vision:${uid}`, 5, 24 * 60 * 60_000);
    const user = (await services().db.doc(`users/${uid}`).get()).data();
    const adultBirthYear = new Date().getUTCFullYear() - 18;
    if (!user || user.photoInsightConsent !== true || typeof user.birthYear !== 'number' || user.birthYear > adultBirthYear) {
      throw new HttpsError('permission-denied', 'Photo insight requires explicit consent from an eligible adult account.');
    }
    if (request.headers.get('content-type')?.split(';')[0] !== 'image/jpeg') throw new HttpsError('invalid-argument', 'Content-Type must be image/jpeg.');
    const declared = Number(request.headers.get('content-length') || 0);
    if (declared > MAX_JPEG_BYTES) throw new HttpsError('invalid-argument', `JPEG exceeds ${MAX_JPEG_BYTES} bytes.`);
    const jpeg = new Uint8Array(await request.arrayBuffer());
    const result = await analyzeJpeg(new TogetherVisionProvider(process.env.TOGETHER_API_KEY || ''), jpeg);
    log.info('photoInsight.completed', { uid, bytes: jpeg.byteLength, model: process.env.TOGETHER_MODEL ? 'configured' : 'default' });
    return ok(result);
  } catch (error) {
    return failure(error, 'photoInsight.failed');
  }
}
