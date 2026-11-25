import { NextResponse } from 'next/server';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export const dynamic = 'force-dynamic';

function runningRevision(): string {
  // The release archive owns this file. Environment values may still describe
  // an older release after the current symlink moves to a new one.
  try {
    const revision = readFileSync(join(process.cwd(), '..', 'REVISION'), 'utf8').trim();
    if (/^[0-9a-f]{7,40}$/.test(revision)) return revision;
  } catch { /* Local development has no release manifest. */ }
  return process.env.APP_REVISION || 'development';
}

export function GET() {
  return NextResponse.json({ status: 'ok', revision: runningRevision() }, {
    headers: { 'Cache-Control': 'no-store' },
  });
}
