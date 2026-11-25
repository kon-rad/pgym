import { HttpsError } from './errors';

export const PRO_ENTITLEMENT = 'pro';
export const REVENUECAT_API_URL = 'https://api.revenuecat.com/v1';

type Fetch = typeof fetch;

interface SubscriberResponse {
  subscriber?: { entitlements?: Record<string, { expires_date?: string | null }> };
}

export class RevenueCatEntitlements {
  constructor(
    private readonly secretApiKey: string,
    private readonly fetchImpl: Fetch = fetch,
  ) {}

  async hasActive(appUserId: string, entitlement: string, now: Date): Promise<boolean> {
    if (!this.secretApiKey) throw new Error('RevenueCat is not configured.');
    const response = await this.fetchImpl(`${REVENUECAT_API_URL}/subscribers/${encodeURIComponent(appUserId)}`, {
      headers: { Authorization: `Bearer ${this.secretApiKey}`, Accept: 'application/json' },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`RevenueCat returned HTTP ${response.status}.`);
    const payload = await response.json() as SubscriberResponse;
    const value = payload.subscriber?.entitlements?.[entitlement];
    if (!value) return false;
    if (value.expires_date === null) return true;
    if (typeof value.expires_date !== 'string') return false;
    const expiresAt = Date.parse(value.expires_date);
    return Number.isFinite(expiresAt) && expiresAt > now.getTime();
  }
}

export async function requireProEntitlement(uid: string): Promise<void> {
  const provider = new RevenueCatEntitlements(process.env.REVENUECAT_SECRET_API_KEY || '');
  try {
    if (await provider.hasActive(uid, PRO_ENTITLEMENT, new Date())) return;
  } catch {
    throw new HttpsError('unavailable', 'Subscription verification is temporarily unavailable.');
  }
  throw new HttpsError('permission-denied', 'An active Pro entitlement is required.');
}
