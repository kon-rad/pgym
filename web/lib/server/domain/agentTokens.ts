/**
 * Personal access tokens for the agent API (architecture note, "Agent access:
 * the API"). A token is `pgym_pat_` plus 40 random base62 characters. It is
 * returned once by createAgentToken; Firestore keeps only its SHA-256 hash in
 * users/{uid}/agentTokens/{tokenId}.
 */
import { createHash, randomBytes } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from '../errors';
import { ID_PATTERN } from './photoStore';
import { CreateAgentTokenInput, RevokeAgentTokenInput, SCOPES, type Scope } from './apiSchemas';
import type { Deps } from './handlers';

export const TOKEN_PREFIX = 'pgym_pat_';
export const TOKEN_RANDOM_LENGTH = 40;
export const TOKEN_PATTERN = /^pgym_pat_[A-Za-z0-9]{40}$/;
/** Characters of the token kept in clear for display: `pgym_pat_` plus the first 8 random characters. */
export const DISPLAY_PREFIX_LENGTH = TOKEN_PREFIX.length + 8;
export const DEFAULT_EXPIRY_DAYS = 90;
/** Active (not revoked, not expired) tokens one user may hold. */
export const MAX_ACTIVE_TOKENS = 20;

const BASE62 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const DAY_MS = 24 * 60 * 60 * 1000;

/** 40 uniformly random base62 characters (rejection sampling, no modulo bias). */
export function randomBase62(length: number): string {
  let out = '';
  while (out.length < length) {
    for (const byte of randomBytes(length * 2)) {
      if (byte < 248) out += BASE62[byte % 62]; // 248 = 4 * 62
      if (out.length === length) break;
    }
  }
  return out;
}

export function generateToken(): string {
  return TOKEN_PREFIX + randomBase62(TOKEN_RANDOM_LENGTH);
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

export interface CreatedToken {
  tokenId: string;
  /** The token itself. Shown once; the server cannot show it again. */
  token: string;
  prefix: string;
  name: string;
  scopes: Scope[];
  createdAt: string;
  expiresAt: string | null;
}

function requireUid(uid: string | undefined): string {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function toMillis(v: unknown): number | null {
  return v instanceof Timestamp ? v.toMillis() : null;
}

export function isActive(doc: FirebaseFirestore.DocumentData, nowMs: number): boolean {
  if (doc.revokedAt) return false;
  const exp = toMillis(doc.expiresAt);
  return exp === null || exp > nowMs;
}

export async function createAgentToken(deps: Deps, authUid: string | undefined, data: unknown): Promise<CreatedToken> {
  const uid = requireUid(authUid);
  const parsed = CreateAgentTokenInput.safeParse(data ?? {});
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.issues.map((i) => `${i.path.join('.') || 'input'}: ${i.message}`).join('; '));
  }
  const input = parsed.data;
  // Keep the canonical order and drop duplicates.
  const scopes = SCOPES.filter((s) => input.scopes.includes(s));
  const now = deps.now();
  const expiresInDays = input.expiresInDays === undefined ? DEFAULT_EXPIRY_DAYS : input.expiresInDays;
  const expiresAt = expiresInDays === null ? null : new Date(now.getTime() + expiresInDays * DAY_MS);

  const col = deps.db.collection(`users/${uid}/agentTokens`);
  const active = (await col.where('revokedAt', '==', null).get()).docs.filter((d) => isActive(d.data(), now.getTime()));
  if (active.length >= MAX_ACTIVE_TOKENS) {
    throw new HttpsError('resource-exhausted', `You can have at most ${MAX_ACTIVE_TOKENS} active tokens. Revoke one first.`);
  }

  const token = generateToken();
  const ref = col.doc();
  const prefix = token.slice(0, DISPLAY_PREFIX_LENGTH);
  await ref.create({
    name: input.name,
    tokenHash: hashToken(token),
    prefix,
    scopes,
    createdAt: Timestamp.fromDate(now),
    lastUsedAt: null,
    expiresAt: expiresAt ? Timestamp.fromDate(expiresAt) : null,
    revokedAt: null,
  });
  deps.log.info('createAgentToken', { uid, tokenId: ref.id, scopes, expiresInDays });
  return {
    tokenId: ref.id,
    token,
    prefix,
    name: input.name,
    scopes,
    createdAt: now.toISOString(),
    expiresAt: expiresAt ? expiresAt.toISOString() : null,
  };
}

export async function revokeAgentToken(
  deps: Deps,
  authUid: string | undefined,
  data: unknown,
): Promise<{ tokenId: string; revokedAt: string }> {
  const uid = requireUid(authUid);
  const parsed = RevokeAgentTokenInput.safeParse(data ?? {});
  if (!parsed.success || !ID_PATTERN.test(parsed.data.tokenId)) {
    throw new HttpsError('invalid-argument', 'tokenId is missing or malformed.');
  }
  const { tokenId } = parsed.data;
  const ref = deps.db.doc(`users/${uid}/agentTokens/${tokenId}`);
  const revokedAt = await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'No such token.');
    const prior = snap.get('revokedAt');
    if (prior instanceof Timestamp) return prior.toDate();
    const at = deps.now();
    tx.update(ref, { revokedAt: Timestamp.fromDate(at) });
    return at;
  });
  deps.log.info('revokeAgentToken', { uid, tokenId });
  return { tokenId, revokedAt: revokedAt.toISOString() };
}
