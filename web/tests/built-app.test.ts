import { spawn, type ChildProcess } from 'node:child_process'
import { existsSync } from 'node:fs'
import { createServer } from 'node:net'
import { join } from 'node:path'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

// Runs against the production build: `npm run build` first, then `npm test`.
// Starts `next start` on a free port with test values for the environment and
// requests every page the site serves.

const ROOT = join(__dirname, '..')
const NEXT_BIN = join(ROOT, 'node_modules', 'next', 'dist', 'bin', 'next')
const TEAM_ID = 'TESTTEAM42'
const BUNDLE_ID = 'com.example.pgym.test'

let server: ChildProcess | undefined
let base = ''
let output = ''

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = createServer()
    srv.unref()
    srv.on('error', reject)
    srv.listen(0, '127.0.0.1', () => {
      const address = srv.address()
      srv.close(() => (typeof address === 'object' && address ? resolve(address.port) : reject(new Error('no port'))))
    })
  })
}

async function waitForServer(url: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (server?.exitCode !== null && server?.exitCode !== undefined) {
      throw new Error(`next start exited with code ${server.exitCode}:\n${output}`)
    }
    try {
      const res = await fetch(url, { redirect: 'manual' })
      if (res.status > 0) return
    } catch {
      // not listening yet
    }
    await new Promise((r) => setTimeout(r, 200))
  }
  throw new Error(`next start did not answer within ${timeoutMs} ms:\n${output}`)
}

beforeAll(async () => {
  if (!existsSync(join(ROOT, '.next', 'BUILD_ID'))) {
    throw new Error('No production build in web/.next. Run `npm run build` before `npm test`.')
  }
  const port = await freePort()
  base = `http://127.0.0.1:${port}`
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    NODE_ENV: 'production',
    PORT: String(port),
    APPLE_TEAM_ID: TEAM_ID,
    IOS_BUNDLE_ID: BUNDLE_ID,
  }
  // No Firestore credentials: the waitlist must answer 503, never reach a real project.
  for (const key of ['FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY', 'FIRESTORE_EMULATOR_HOST']) {
    delete env[key]
  }
  server = spawn(process.execPath, [NEXT_BIN, 'start', '-p', String(port), '-H', '127.0.0.1'], {
    cwd: ROOT,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  server.stdout?.on('data', (d) => (output += String(d)))
  server.stderr?.on('data', (d) => (output += String(d)))
  await waitForServer(`${base}/robots.txt`, 45_000)
})

afterAll(async () => {
  if (!server || server.exitCode !== null) return
  const exited = new Promise((r) => server?.once('exit', r))
  server.kill('SIGTERM')
  await Promise.race([exited, new Promise((r) => setTimeout(r, 5_000))])
  if (server.exitCode === null) server.kill('SIGKILL')
})

const PAGES: [path: string, mustContain: string][] = [
  ['/', 'Proof of gym'],
  ['/privacy', 'Privacy policy'],
  ['/terms', 'Terms of use'],
  ['/support', 'Support'],
  ['/delete-account', 'Delete your account'],
  ['/proof/abc123', 'Shared proofs open here soon.'],
]

describe('built app', () => {
  it.each(PAGES)('GET %s returns 200 with its page', async (path, text) => {
    const res = await fetch(base + path, { redirect: 'manual' })
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toContain('text/html')
    const html = await res.text()
    expect(html).toContain(text)
  })

  it('home page shows the waitlist form while the app is not live', async () => {
    const html = await (await fetch(`${base}/`)).text()
    expect(html).toContain('action="/api/waitlist"')
    expect(html).toContain('Join the waitlist')
    expect(html).not.toContain('Download on the')
  })

  it('pages load no third-party script and no font CDN', async () => {
    const html = await (await fetch(`${base}/`)).text()
    const srcs = [...html.matchAll(/<(?:script|link)[^>]+(?:src|href)="([^"]+)"/g)].map((m) => m[1])
    const external = srcs.filter((s) => /^https?:\/\//.test(s) || s.startsWith('//'))
    expect(external).toEqual([])
    expect(html).not.toMatch(/fonts\.googleapis|fonts\.gstatic|googletagmanager|google-analytics|plausible|segment/)
    expect(html).toMatch(/\/_next\/static\/media\/[^"]+\.woff2/)
  })

  it('any proof id returns the same coming-soon page and is not indexed', async () => {
    const res = await fetch(`${base}/proof/${encodeURIComponent('<script>x</script>')}`)
    expect(res.status).toBe(200)
    const html = await res.text()
    expect(html).toContain('Shared proofs open here soon.')
    expect(html).not.toContain('<script>x</script>')
    expect(html).toMatch(/<meta name="robots" content="noindex/)
  })

  it('serves apple-app-site-association as JSON with the team and bundle ID from the environment', async () => {
    const res = await fetch(`${base}/.well-known/apple-app-site-association`, { redirect: 'manual' })
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toBe('application/json')
    const body = await res.json()
    expect(body.applinks.details[0].appIDs).toEqual([`${TEAM_ID}.${BUNDLE_ID}`])
    expect(body.webcredentials.apps).toEqual([`${TEAM_ID}.${BUNDLE_ID}`])
  })

  it('serves the Open Graph image as a PNG and links it from the page', async () => {
    const res = await fetch(`${base}/opengraph-image`)
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toBe('image/png')
    const bytes = new Uint8Array(await res.arrayBuffer())
    expect([...bytes.slice(0, 4)]).toEqual([0x89, 0x50, 0x4e, 0x47])
    const html = await (await fetch(`${base}/`)).text()
    expect(html).toMatch(/<meta property="og:image" content="[^"]*\/opengraph-image/)
  })

  it.each([
    ['/robots.txt', 'text/plain'],
    ['/sitemap.xml', 'application/xml'],
    ['/icon.svg', 'image/svg+xml'],
  ])('GET %s returns 200', async (path, type) => {
    const res = await fetch(base + path)
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toContain(type)
  })

  it('an unknown path returns 404 with the designed not-found page', async () => {
    const res = await fetch(`${base}/no-such-page`)
    expect(res.status).toBe(404)
    expect(await res.text()).toContain('No proof of this page.')
  })

  it('/404 itself renders the not-found page with status 404', async () => {
    const res = await fetch(`${base}/404`)
    expect(res.status).toBe(404)
    expect(await res.text()).toContain('No proof of this page.')
  })

  it('the waitlist route validates before it touches the store', async () => {
    const res = await fetch(`${base}/api/waitlist`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-forwarded-for': '198.51.100.200' },
      body: JSON.stringify({ email: 'not-an-email' }),
    })
    expect(res.status).toBe(400)
    expect(await res.json()).toMatchObject({ ok: false, status: 'invalid' })
  })

  it('the waitlist route answers 503 when Firestore is not configured', async () => {
    const res = await fetch(`${base}/api/waitlist`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-forwarded-for': '198.51.100.201' },
      body: JSON.stringify({ email: 'lifter@example.com' }),
    })
    expect(res.status).toBe(503)
    expect(await res.json()).toMatchObject({ ok: false, status: 'unavailable' })
  })

  it('the waitlist route only accepts POST', async () => {
    const res = await fetch(`${base}/api/waitlist`)
    expect(res.status).toBe(405)
  })
})
