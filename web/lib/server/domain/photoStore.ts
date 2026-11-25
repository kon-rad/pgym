/**
 * Every S3 call the functions make goes through this interface. There are two
 * implementations: `S3PhotoStore` (AWS S3 or a local S3-compatible server such
 * as MinIO, picked by endpoint) and the in-memory fake the tests use.
 */
export interface PhotoStore {
  /** Presigned PUT; content type and exact byte length are part of the signature. */
  presignPut(key: string, contentType: string, contentLength: number, expiresInSec: number): Promise<string>;
  /** Presigned GET. */
  presignGet(key: string, expiresInSec: number): Promise<string>;
  /** True when the object exists. */
  exists(key: string): Promise<boolean>;
  /** Every key under `prefix`. */
  listKeys(prefix: string): Promise<string[]>;
  /** Delete each key. Missing keys are not an error. */
  deleteKeys(keys: string[]): Promise<void>;
  /** The object's bytes. Rejects when it is missing or larger than `maxBytes`. Used by analyzePhysique. */
  getBytes(key: string, maxBytes: number): Promise<Uint8Array>;
}

export const PUT_EXPIRES_SEC = 5 * 60;
export const GET_EXPIRES_SEC = 60 * 60;
export const PHOTO_CONTENT_TYPE = 'image/jpeg';
/** A 2048 px JPEG is 1 to 3 MB; anything above this is not a phone photo. */
export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;

export const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export function userPrefix(uid: string): string {
  return `users/${uid}/`;
}

export function photoKey(uid: string, sessionId: string): string {
  return `users/${uid}/sessions/${sessionId}/photo.jpg`;
}

export function cardKey(uid: string, sessionId: string): string {
  return `users/${uid}/sessions/${sessionId}/card.jpg`;
}

/** True when `key` is a photo or card key that belongs to `uid`. */
export function isOwnKey(uid: string, key: unknown): key is string {
  if (typeof key !== 'string') return false;
  const m = /^users\/([^/]+)\/sessions\/([^/]+)\/(photo|card)\.jpg$/.exec(key);
  return m !== null && m[1] === uid && ID_PATTERN.test(m[2]);
}
