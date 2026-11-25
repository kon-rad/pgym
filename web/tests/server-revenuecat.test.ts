import { describe, expect, it, vi } from 'vitest';
import { RevenueCatEntitlements } from '../lib/server/revenuecat';

const NOW = new Date('2026-11-25T12:00:00Z');
const response = (entitlements: Record<string, unknown>) => new Response(JSON.stringify({ subscriber: { entitlements } }), {
  status: 200,
  headers: { 'content-type': 'application/json' },
});

describe('RevenueCat Pro entitlement provider', () => {
  it.each([
    ['future expiration', { pro: { expires_date: '2026-11-26T12:00:00Z' } }],
    ['lifetime entitlement', { pro: { expires_date: null } }],
  ])('accepts active Pro with %s', async (_label, entitlements) => {
    const fetchMock = vi.fn().mockResolvedValue(response(entitlements));
    await expect(new RevenueCatEntitlements('server-secret', fetchMock).hasActive('firebase uid/1', 'pro', NOW)).resolves.toBe(true);
    expect(fetchMock.mock.calls[0][0]).toBe('https://api.revenuecat.com/v1/subscribers/firebase%20uid%2F1');
    expect((fetchMock.mock.calls[0][1] as RequestInit).headers).toMatchObject({ Authorization: 'Bearer server-secret' });
  });

  it.each([
    ['missing entitlement', {}],
    ['expired entitlement', { pro: { expires_date: '2026-11-25T11:59:59Z' } }],
    ['malformed expiration', { pro: { expires_date: 'not-a-date' } }],
  ])('rejects %s', async (_label, entitlements) => {
    const fetchMock = vi.fn().mockResolvedValue(response(entitlements));
    await expect(new RevenueCatEntitlements('server-secret', fetchMock).hasActive('owner', 'pro', NOW)).resolves.toBe(false);
  });

  it('fails closed when the provider or server configuration is unavailable', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('offline', { status: 503 }));
    await expect(new RevenueCatEntitlements('server-secret', fetchMock).hasActive('owner', 'pro', NOW)).rejects.toThrow('HTTP 503');
    await expect(new RevenueCatEntitlements('').hasActive('owner', 'pro', NOW)).rejects.toThrow('not configured');
  });
});
