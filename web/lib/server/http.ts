import { NextResponse } from 'next/server';
import { HttpsError } from './errors';
import { services } from './firebase';
import { log } from './log';
import { triggerLazyWeekRollover } from './rollover';

const STATUS: Record<string, number> = {
  unauthenticated: 401,
  'permission-denied': 403,
  'not-found': 404,
  'invalid-argument': 400,
  'failed-precondition': 409,
  'resource-exhausted': 429,
  unimplemented: 501,
};

export async function uidFromRequest(request: Request): Promise<string> {
  const header = request.headers.get('authorization') || '';
  const match = /^Bearer (\S+)$/.exec(header);
  if (!match) throw new HttpsError('unauthenticated', 'A Firebase ID token is required.');
  try {
    const uid = (await services().auth.verifyIdToken(match[1], true)).uid;
    void triggerLazyWeekRollover();
    return uid;
  } catch {
    throw new HttpsError('unauthenticated', 'The Firebase ID token is invalid or expired.');
  }
}

export async function jsonBody(request: Request, maxBytes = 32_768): Promise<unknown> {
  const declared = Number(request.headers.get('content-length') || 0);
  if (declared > maxBytes) throw new HttpsError('invalid-argument', `Request body exceeds ${maxBytes} bytes.`);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > maxBytes) throw new HttpsError('invalid-argument', `Request body exceeds ${maxBytes} bytes.`);
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpsError('invalid-argument', 'Request body must be valid JSON.');
  }
}

export function ok(body: unknown, status = 200) {
  return NextResponse.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
}

export function failure(error: unknown, event: string) {
  const known = error instanceof HttpsError;
  const status = known ? (STATUS[error.code] || 500) : 500;
  log.warn(event, { status, code: known ? error.code : 'internal', error: known ? error.message : String(error) });
  return NextResponse.json(
    { error: { code: known ? error.code : 'internal', message: known ? error.message : 'The request could not be completed.' } },
    { status, headers: { 'Cache-Control': 'no-store' } },
  );
}

export async function authenticated(
  request: Request,
  event: string,
  run: (uid: string, body: unknown) => Promise<unknown>,
  options: { body?: boolean; status?: number } = { body: true },
) {
  try {
    const uid = await uidFromRequest(request);
    const body = options.body === false ? undefined : await jsonBody(request);
    return ok(await run(uid, body), options.status || 200);
  } catch (error) {
    return failure(error, event);
  }
}
