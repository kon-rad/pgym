import { describe, expect, it, vi } from 'vitest';
import { RevenueCatEntitlements } from '../lib/server/revenuecat';

const NOW = new Date('2026-11-25T12:00:00Z');
const response = (items: unknown[]) => new Response(JSON.stringify({ items }), {
  status: 200,
  headers: { 'content-type': 'application/json' },
});

describe('RevenueCat Pro entitlement provider', () => {
  it.each([
    ['future expiration', [{ entitlement_id: 'entl_pro', expires_at: NOW.getTime() + 86_400_000 }]],
    ['lifetime entitlement', [{ entitlement_id: 'entl_pro', expires_at: null }]],
  ])('accepts active Pro with %s', async (_label, items) => {
    const fetchMock = vi.fn().mockResolvedValue(response(items));
    await expect(new RevenueCatEntitlements('server-secret', 'project/1', 'entl_pro', fetchMock).hasActive('firebase uid/1', NOW)).resolves.toBe(true);
    expect(fetchMock.mock.calls[0][0]).toBe('https://api.revenuecat.com/v2/projects/project%2F1/customers/firebase%20uid%2F1/active_entitlements');
    expect((fetchMock.mock.calls[0][1] as RequestInit).headers).toMatchObject({ Authorization: 'Bearer server-secret' });
  });

  it.each([
    ['missing entitlement', []],
    ['different entitlement', [{ entitlement_id: 'entl_other', expires_at: NOW.getTime() + 86_400_000 }]],
    ['expired entitlement', [{ entitlement_id: 'entl_pro', expires_at: NOW.getTime() - 1 }]],
    ['malformed expiration', [{ entitlement_id: 'entl_pro', expires_at: 'not-a-date' }]],
  ])('rejects %s', async (_label, items) => {
    const fetchMock = vi.fn().mockResolvedValue(response(items));
    await expect(new RevenueCatEntitlements('server-secret', 'project', 'entl_pro', fetchMock).hasActive('owner', NOW)).resolves.toBe(false);
  });

  it('treats a customer not found response as inactive', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('missing', { status: 404 }));
    await expect(new RevenueCatEntitlements('server-secret', 'project', 'entl_pro', fetchMock).hasActive('owner', NOW)).resolves.toBe(false);
  });

  it('fails closed when the provider or server configuration is unavailable', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('offline', { status: 503 }));
    await expect(new RevenueCatEntitlements('server-secret', 'project', 'entl_pro', fetchMock).hasActive('owner', NOW)).rejects.toThrow('HTTP 503');
    await expect(new RevenueCatEntitlements('', '', '').hasActive('owner', NOW)).rejects.toThrow('not configured');
  });
});
