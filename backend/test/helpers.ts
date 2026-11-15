import { randomUUID } from 'node:crypto';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import type { Deps, Logger } from '../src/handlers';
import type { PhotoStore } from '../src/photoStore';

export const PROJECT_ID = 'pgym-local';

export function requireEmulator(): void {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('Run these tests with `npm test`, which starts the Firestore and Auth emulators.');
  }
}

export function adminDb(): Firestore {
  requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  return getFirestore();
}

export function adminAuth() {
  adminDb();
  return getAuth();
}

/** A user ID no other test uses, so tests never need to clear the emulator. */
export function newUid(label: string): string {
  return `${label}-${randomUUID().slice(0, 8)}`;
}

/** In-memory PhotoStore that records every call. */
export class FakePhotoStore implements PhotoStore {
  readonly objects = new Map<string, number>();
  readonly deleted: string[] = [];
  readonly signedPuts: Array<{ key: string; contentType: string; contentLength: number; expiresInSec: number }> = [];

  put(key: string, bytes = 1000): void {
    this.objects.set(key, bytes);
  }

  async presignPut(key: string, contentType: string, contentLength: number, expiresInSec: number): Promise<string> {
    this.signedPuts.push({ key, contentType, contentLength, expiresInSec });
    return `https://s3.test/${key}?op=put&expires=${expiresInSec}`;
  }

  async presignGet(key: string, expiresInSec: number): Promise<string> {
    return `https://s3.test/${key}?op=get&expires=${expiresInSec}`;
  }

  async exists(key: string): Promise<boolean> {
    return this.objects.has(key);
  }

  async listKeys(prefix: string): Promise<string[]> {
    return [...this.objects.keys()].filter((k) => k.startsWith(prefix));
  }

  async deleteKeys(keys: string[]): Promise<void> {
    for (const k of keys) {
      this.deleted.push(k);
      this.objects.delete(k);
    }
  }

  async getBytes(key: string, maxBytes: number): Promise<Uint8Array> {
    const size = this.objects.get(key);
    if (size === undefined) throw new Error(`no such object: ${key}`);
    if (size > maxBytes) throw new Error('too large');
    return new Uint8Array(size);
  }
}

export const silentLog: Logger = { info: () => undefined, warn: () => undefined };

export function testDeps(overrides: Partial<Deps> = {}): Deps & { store: FakePhotoStore } {
  return {
    db: adminDb(),
    auth: adminAuth(),
    store: new FakePhotoStore(),
    now: () => new Date('2026-11-18T18:00:00Z'),
    log: silentLog,
    ...overrides,
  } as Deps & { store: FakePhotoStore };
}
