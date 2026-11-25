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
  ['/guide', 'How to use PGYM'],
  ['/blog', 'Why proof of gym'],
  ['/blog/why-proof-of-gym', 'Most of training is showing up.'],
  ['/agents', 'For your agent'],
  ['/open-source', 'Open source'],
]

// Footer links every page carries (pgym-landing-pages.md, home section 11).
const FOOTER = ['/guide', '/blog', '/agents', '/skill.md', '/open-source', '/privacy', '/terms', '/support', '/delete-account']

describe('built app', () => {
  it.each(PAGES)('GET %s returns 200 with its page', async (path, text) => {
    const res = await fetch(base + path, { redirect: 'manual' })
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toContain('text/html')
    const html = await res.text()
    expect(html).toContain(text)
  })

  it.each(PAGES.map(([path]) => path))('%s links every footer page', async (path) => {
    const html = await (await fetch(base + path)).text()
    const footer = html.slice(html.indexOf('<footer'))
    for (const href of FOOTER) expect(footer).toContain(`href="${href}"`)
    expect(footer).toContain('href="https://github.com/kon-rad/pgym"')
  })

  it('serves /skill.md as markdown with its skill frontmatter', async () => {
    const res = await fetch(`${base}/skill.md`)
    expect(res.status).toBe(200)
    expect(res.headers.get('content-type')).toContain('text/markdown')
    const text = await res.text()
    expect(text.startsWith('---\nname: pgym\ndescription: ')).toBe(true)
    expect(text).not.toContain('<!--')
  })

  it('an unknown blog post is a 404', async () => {
    const res = await fetch(`${base}/blog/no-such-post`)
    expect(res.status).toBe(404)
  })

  it.each(['/privacy', '/terms'])('%s keeps the draft line visible', async (path) => {
    const html = await (await fetch(base + path)).text()
    expect(html).toContain('DRAFT, not reviewed by a lawyer')
  })

  it('home page shows the stamped proof card and the log, photo, card sequence', async () => {
    const html = await (await fetch(`${base}/`)).text()
    expect(html).toContain('viewBox="0 0 1080 1350"')
    expect(html).toContain('pc-stamp-animate')
    expect(html).toContain('>7 WEEKS RUNNING<')
    expect(html).toContain('ld-frame-log')
    expect(html).toContain('ld-frame-photo')
    expect(html).toContain('ld-frame-card')
    expect(html).toContain('href="/open-source"')
    expect(html).toContain('href="/agents"')
  })

  it('home page carries the final landing copy (pgym-landing-copy.md)', async () => {
    const html = (await (await fetch(`${base}/`)).text()).replace(/&#x27;|&#39;/g, "'")
    for (const line of [
      'Log your sets. Take one photo. Get your proof.',
      'iPhone only. Not out yet.',
      'How it works',
      'Every session, numbered.',
      'Iron. Chalk. Plate. Raw.',
      'A streak that counts weeks.',
      'Watch it add up.',
      'Private by default.',
      'Proof #001 is waiting',
      'Built in the open.',
      'The code is on GitHub.',
      'Your agent can read your training.',
      '<title>PGYM: Proof of gym for your iPhone</title>',
    ]) {
      expect(html, line).toContain(line)
    }
    const questions = [...html.matchAll(/<summary>([^<]+)<\/summary>/g)].map((m) => m[1])
    expect(questions).toEqual([
      'Is it free?',
      'Which phones does it work on?',
      'What happens to my photos?',
      'How does optional AI analysis work?',
      'What counts as a proof?',
      'What if I miss a week?',
      'Does it work without signal?',
      'Can I see the code?',
    ])
  })

  it('home page has the nav button only as an outline, and the hero form keeps the one Plate action', async () => {
    const html = await (await fetch(`${base}/`)).text()
    const header = html.slice(html.indexOf('<header'), html.indexOf('</header>'))
    expect(header).toContain('btn btn-secondary nav-btn')
    expect(header).not.toContain('btn-primary')
    expect(html).toContain('id="hero-email"')
  })

  it('/privacy sets the photo and AI section apart and lists its contents', async () => {
    const html = await (await fetch(`${base}/privacy`)).text()
    expect(html).toContain('<section id="photos-and-optional-ai-insight"')
    expect(html).toContain('<nav class="doc-toc" aria-label="Contents">')
    expect(html).toContain('Last updated 2026-11-25')
  })

  it('/support carries the support copy', async () => {
    const html = await (await fetch(`${base}/support`)).text()
    for (const q of ['I cannot sign in.', 'My proof says pending.', 'How do I get a copy of my data?', 'Found a security problem?']) {
      expect(html).toContain(q)
    }
    expect(html).toContain('https://[DOMAIN]/delete-account')
  })

  it('/open-source and /terms name the MIT licence without calling it proposed', async () => {
    for (const path of ['/open-source', '/terms']) {
      const html = await (await fetch(base + path)).text()
      expect(html).toContain('MIT')
      expect(html).not.toMatch(/proposed and not yet confirmed|MIT is proposed/)
    }
  })

  it('home page copy stays positive', async () => {
    const html = (await (await fetch(`${base}/`)).text()).toLowerCase()
    for (const phrase of ['broke your streak', 'break your streak', 'lost your streak', "don't break", 'you failed', 'shame']) {
      expect(html).not.toContain(phrase)
    }
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
    expect(await res.text()).toContain('No proof here.')
  })

  it('/404 itself renders the not-found page with status 404', async () => {
    const res = await fetch(`${base}/404`)
    expect(res.status).toBe(404)
    expect(await res.text()).toContain('No proof here.')
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
