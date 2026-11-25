import { HttpsError } from './errors';

export const PRO_ENTITLEMENT = 'pro';
export const REVENUECAT_API_URL = 'https://api.revenuecat.com/v2';

type Fetch = typeof fetch;

interface ActiveEntitlementsResponse {
  items?: Array<{ entitlement_id?: string; expires_at?: number | null }>;
}

export class RevenueCatEntitlements {
  constructor(
    private readonly secretApiKey: string,
    private readonly projectId: string,
    private readonly entitlementId: string,
    private readonly fetchImpl: Fetch = fetch,
  ) {}

  async hasActive(appUserId: string, now: Date): Promise<boolean> {
    if (!this.secretApiKey || !this.projectId || !this.entitlementId) throw new Error('RevenueCat is not configured.');
    const response = await this.fetchImpl(
      `${REVENUECAT_API_URL}/projects/${encodeURIComponent(this.projectId)}/customers/${encodeURIComponent(appUserId)}/active_entitlements`, {
      headers: { Authorization: `Bearer ${this.secretApiKey}`, Accept: 'application/json' },
      signal: AbortSignal.timeout(10_000),
      },
    );
    if (response.status === 404) return false;
    if (!response.ok) throw new Error(`RevenueCat returned HTTP ${response.status}.`);
    const payload = await response.json() as ActiveEntitlementsResponse;
    const value = payload.items?.find((item) => item.entitlement_id === this.entitlementId);
    if (!value) return false;
    if (value.expires_at === null) return true;
    return typeof value.expires_at === 'number' && Number.isFinite(value.expires_at) && value.expires_at > now.getTime();
  }
}

export async function requireProEntitlement(uid: string): Promise<void> {
  const provider = new RevenueCatEntitlements(
    process.env.REVENUECAT_SECRET_API_KEY || '',
    process.env.REVENUECAT_PROJECT_ID || '',
    process.env.REVENUECAT_PRO_ENTITLEMENT_ID || '',
  );
  try {
    if (await provider.hasActive(uid, new Date())) return;
  } catch {
    throw new HttpsError('unavailable', 'Subscription verification is temporarily unavailable.');
  }
  throw new HttpsError('permission-denied', 'An active Pro entitlement is required.');
}
