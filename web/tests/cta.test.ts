import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { afterEach, describe, expect, it, vi } from 'vitest'

// The one launch flag: NEXT_PUBLIC_APP_LIVE=true plus an App Store URL turns every
// call to action into the App Store badge. lib/site.ts reads the environment when
// it is imported, so each case re-imports it with a fresh module registry.

async function render(env: Record<string, string>) {
  vi.resetModules()
  for (const [k, v] of Object.entries(env)) vi.stubEnv(k, v)
  const { CallToAction, HeaderAction } = await import('@/components/CallToAction')
  return {
    cta: renderToStaticMarkup(createElement(CallToAction, { source: 'hero' })),
    header: renderToStaticMarkup(createElement(HeaderAction)),
  }
}

afterEach(() => vi.unstubAllEnvs())

describe('launch flag', () => {
  it('shows the waitlist form while the flag is off', async () => {
    const { cta, header } = await render({ NEXT_PUBLIC_APP_LIVE: '', NEXT_PUBLIC_APP_STORE_URL: '' })
    expect(cta).toContain('action="/api/waitlist"')
    expect(cta).toContain('value="hero"')
    // The form note names the App Store in its copy; the badge itself must not be there.
    expect(cta).not.toContain('store-badge')
    expect(cta).not.toContain('Download on the')
    expect(header).toContain('Join the waitlist')
    expect(header).not.toContain('btn-primary')
  })

  it('shows the App Store badge when the flag is on and a URL is set', async () => {
    const url = 'https://apps.apple.com/app/id0000000000'
    const { cta, header } = await render({ NEXT_PUBLIC_APP_LIVE: 'true', NEXT_PUBLIC_APP_STORE_URL: url })
    expect(cta).toContain(`href="${url}"`)
    expect(cta).toContain('App Store')
    expect(cta).not.toContain('<form')
    expect(header).toContain('Get the app')
  })

  it('stays on the waitlist when the flag is on but no URL is set', async () => {
    const { cta } = await render({ NEXT_PUBLIC_APP_LIVE: 'true', NEXT_PUBLIC_APP_STORE_URL: '' })
    expect(cta).toContain('action="/api/waitlist"')
  })
})
