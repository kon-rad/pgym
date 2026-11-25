import { handleApi } from '@/lib/server/domain/api';
import { services } from '@/lib/server/firebase';
import { NextResponse } from 'next/server';
import { triggerLazyWeekRollover } from '@/lib/server/rollover';

async function route(request: Request, context: { params: Promise<{ path: string[] }> }) {
  const { path } = await context.params;
  void triggerLazyWeekRollover();
  const url = new URL(request.url);
  const result = await handleApi(services(), {
    method: request.method,
    path: `/v1/${path.join('/')}`,
    query: Object.fromEntries(url.searchParams),
    headers: Object.fromEntries(request.headers),
  });
  return NextResponse.json(result.body, { status: result.status, headers: result.headers });
}

export const GET = route;
export const HEAD = route;
