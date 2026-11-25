# PGYM web and API service

The single PGYM production process: Next.js landing pages, waitlist, authenticated iOS operations, transient photo insight, health endpoint and read-only agent API. No analytics script.

Production dependencies are Firebase Authentication, Firestore and Together AI. Firebase Cloud Functions, Firebase AI Logic, Gemini, AWS and server-side photo storage are not used. The default open-source vision model is `Qwen/Qwen3-VL-8B-Instruct`, configurable with `TOGETHER_MODEL`. The request is a reduced JPEG up to 1.5 MB; neither bytes nor model output are logged or persisted.

## Run it

```sh
npm ci
# optional: put variables from "Environment" below in .env.local; all have safe defaults
npm run dev                  # http://localhost:3000
```

The waitlist needs Firestore. Locally, run the emulator from `backend/` and set
`FIREBASE_PROJECT_ID=pgym-local` and `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`.
Without either, the form answers "not taking signups right now" (HTTP 503).

## Checks

```sh
npm run lint    # eslint + tsc
npm run build
npm test        # needs the build: starts `next start` and requests every page
```

Tests never reach Firestore: the waitlist tests inject an in-memory store, and the
built-app test starts the server with no Firebase credentials.

## API routes

- `POST /api/sessions/stamp`, `DELETE /api/sessions/{id}`, `DELETE /api/account`
- `POST /api/agent-tokens`, `DELETE /api/agent-tokens/{id}`
- `POST /api/photo-insight` with a raw `image/jpeg` body
- `GET /v1/...` for scoped, read-only personal tokens
- `GET /api/health` with the running `APP_REVISION`

Authenticated operation routes require `Authorization: Bearer <Firebase ID token>`. Week rollover runs lazily under active traffic. `deploy/` contains systemd, Caddy, release verification and explicit-host deployment templates.

After `npm run build`, package and validate a revision without contacting a host:

```sh
./deploy/package-release.sh abc1234 /tmp/pgym-abc1234.tar.gz
./deploy/deploy.sh --host deploy-user@[DOMAIN] --revision abc1234 --artifact /tmp/pgym-abc1234.tar.gz --dry-run
```

## Pages

| Path | What |
|---|---|
| `/` | Landing page with the waitlist form (or the App Store badge) |
| `/privacy`, `/terms` | The privacy policy and terms drafts from `content/privacy.md` and `content/terms.md`, under a visible "DRAFT, not reviewed by a lawyer" line |
| `/support`, `/delete-account` | Contact, common questions, account deletion |
| `/proof/[id]` | Reserved for shared proofs (v1.1); a coming-soon page for now |
| `/guide` | How to use PGYM, from `content/guide.md` |
| `/blog`, `/blog/[slug]` | Posts from `content/blog/*.md`; an unknown slug is a 404 |
| `/agents` | For your agent: tokens, scopes, endpoints, from `content/agents.md` |
| `/open-source` | The repo, licence, running it locally, security reports, from `content/open-source.md` |
| `/skill.md` | The agent skill file as `text/markdown`, frontmatter kept, from `content/skill.md` |
| `/.well-known/apple-app-site-association` | JSON, app ID from `APPLE_TEAM_ID` and `IOS_BUNDLE_ID` |
| `/api/waitlist` | `POST`, JSON or form. Validates the email, 5 requests a minute per IP, writes `waitlist/{sha256(email)}` once |
| `/opengraph-image`, `/robots.txt`, `/sitemap.xml`, `/icon.svg` | Generated |

## Environment

Never commit real values. `NEXT_PUBLIC_*` are inlined at build time, so changing
one needs a rebuild; the rest are read at request time.

| Variable | Needed for | If unset |
|---|---|---|
| `NEXT_PUBLIC_SITE_URL` | Canonical URL for Open Graph, sitemap, robots (`https://[DOMAIN]`) | `http://localhost:3000` |
| `NEXT_PUBLIC_SUPPORT_EMAIL` | Support address on every page | `[EMAIL]` placeholder, no link |
| `NEXT_PUBLIC_OPERATOR_NAME` | Legal name in the footer, support page and legal pages (`[COMPANY]`) | `[COMPANY]` placeholder |
| `NEXT_PUBLIC_OPERATOR_ADDRESS` | Postal address on the support page and legal pages (`[ADDRESS]`) | `[ADDRESS]` placeholder |
| `NEXT_PUBLIC_API_URL` | Agent API host in the example request | `https://[API-DOMAIN]` |
| `NEXT_PUBLIC_APP_LIVE` | The launch flag, `true` to switch on | Waitlist |
| `NEXT_PUBLIC_APP_STORE_URL` | App Store link; the flag needs it | Waitlist |
| `APPLE_TEAM_ID` | apple-app-site-association | `TEAMID0000` |
| `IOS_BUNDLE_ID` | apple-app-site-association | `com.example.pgym` |
| `FIREBASE_PROJECT_ID` | Waitlist writes | Waitlist answers 503 |
| `FIREBASE_CLIENT_EMAIL` | Waitlist writes (service account) | Waitlist answers 503 |
| `FIREBASE_PRIVATE_KEY` | Waitlist writes; newlines as `\n` | Waitlist answers 503 |
| `FIRESTORE_EMULATOR_HOST` | Local only, instead of the two credentials above | Uses real credentials |
| `GOOGLE_APPLICATION_CREDENTIALS` | Firebase Admin application-default credentials | API operations unavailable |
| `TOGETHER_API_KEY` | Transient photo insight | Photo insight answers 409 |
| `TOGETHER_MODEL` | Open-source Together vision model | `Qwen/Qwen3-VL-8B-Instruct` |
| `APP_REVISION` | Health and exact-release verification | `development` |
| `PORT`, `HOSTNAME` | Standalone Next.js listener | Next.js defaults |

## The launch flag

Set `NEXT_PUBLIC_APP_LIVE=true` and `NEXT_PUBLIC_APP_STORE_URL` and rebuild. Every
call to action becomes the App Store badge. The badge is drawn in the badge
layout; replace it with Apple's official badge artwork before launch.

## Content

`content/*.md` are the site copy from the PGYM notes, copied unchanged except
that the vault-only HTML comments are removed. Each has `title`, `description`
and `path` frontmatter; posts add `slug`, `author` and `date` (`[PUBLISH-DATE]`
shows as "Draft"). `[DOMAIN]`, `[API-DOMAIN]`, `[EMAIL]`, `[COMPANY]` and `[ADDRESS]` are filled
at build time from `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_API_URL`,
`NEXT_PUBLIC_SUPPORT_EMAIL`, `NEXT_PUBLIC_OPERATOR_NAME` and
`NEXT_PUBLIC_OPERATOR_ADDRESS` when those are set, and stay as placeholders when
not. `privacy.md` and `terms.md` are Part 1 of the vault's legal drafts; their
bracketed italic notes for counsel stay visible until a lawyer has reviewed them.
Pages render through one document template (`components/DocPage.tsx`): pages
with four or more `##` sections get a contents list.

The home page copy is `pgym-landing-copy.md`, word for word, in `app/page.tsx`,
`components/LoopDemo.tsx`, `app/support/page.tsx` and `lib/waitlist/messages.ts`. Raw HTML in the markdown is shown as text, never rendered.

## Proof card and motion

`components/ProofCard.tsx` draws the card from the 4:5 template
(`pgym-card-4x5.svg`) at its own 1080 x 1350 coordinates, with the four filters
as SVG filter chains on the photo only. The photo is an illustration of gym
equipment, never a person. `components/AppScreens.tsx` draws the app screens
(D2, D7, D8, D11, E1, E2) in HTML inside CSS phone frames, until the simulator
screenshots exist. `components/LoopDemo.tsx` is the home page's log, photo, card
sequence across three frames: CSS only, one 9 s timeline, paused until it scrolls
into view. With `prefers-reduced-motion: reduce`, every animation and hover
movement is off, the stamp fades in over 150 ms, and the sequence is a still of
the finished card.

## Fonts

Anton, Archivo and JetBrains Mono are self-hosted from `app/fonts` (SIL Open Font
Licence, see `OFL-*.txt`). The two `.woff` files exist for the Open Graph image,
whose renderer does not read WOFF2.
