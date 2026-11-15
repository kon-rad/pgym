# backend

Firebase Cloud Functions (2nd gen, TypeScript, Node 20+) and the Firestore security rules for PGYM. Design: the architecture note's "Data model", "S3 layout", "Flow: finishing a session" and "Functions" sections.

## Run the checks

Needs Node 20 or later and Java 11 or later (the Firestore emulator is a Java program).

```sh
npm ci
npm run lint      # eslint and a type check, including the tests
npm run build     # compiles src/ to lib/
npm test          # starts the Firestore and Auth emulators, runs every test, stops them
```

`npm run test:unit` runs only the tests that need no emulator (the streak table, S3 presigning, the OpenAPI document, and every physique rule against an in-memory repo and a fake model).

No test calls AWS or any paid API: the functions take a `PhotoStore` and a `VisionModel`, and the tests pass in-memory fakes. The Gemini client's tests replace `fetch`.

## What is here

| File | Holds |
|---|---|
| `firestore.rules` | A user reads and writes only their own documents. Server-owned fields cannot be written by a client. Stamped sessions are read-only. Deletes go through functions |
| `firestore.indexes.json` | Sessions by status and start time, by status, week and start time; token-hash lookup for the agent API |
| `src/streak.ts` | Pure weekly-streak logic: week keys in the user's timezone, goal locked per week, pass weeks |
| `src/sessionStats.ts` | Pure set counts, total volume, best set and estimated one-rep max |
| `src/photoStore.ts` | The `PhotoStore` interface and the S3 key layout |
| `src/s3PhotoStore.ts` | `PhotoStore` on the AWS SDK v3 client and presigner; works with AWS S3 or MinIO |
| `src/handlers.ts` | The logic of each function, with Firestore, the store and the clock passed in |
| `src/agentTokens.ts` | Personal access tokens: generation, SHA-256 hashing, `createAgentToken`, `revokeAgentToken` |
| `src/apiSchemas.ts` | The agent API's zod schemas and route table, and the OpenAPI 3.1 document built from them |
| `src/api.ts` | The agent API: token lookup, rate limit, scope checks, the six `/v1` endpoints |
| `src/physiquePrompt.ts` | The physique prompt, the JSON response schema `{usable, refusedReason, score, tip}`, the pinned model ID. Public on purpose |
| `src/physique.ts` | `analyzePhysique`: consent and age gate, one analysis per session, 3 per local day, validation, clamping, tip cut and check, smoothing |
| `src/physiqueRepo.ts` | Where the result lives: `physique` on the session document, in Firestore |
| `src/visionModel.ts` | The `VisionModel` interface and `GeminiClient` (REST, key in a header) |
| `src/physiqueEval.ts`, `scripts/physique-eval.ts` | The stability check behind `npm run eval` |
| `src/index.ts` | The exported Cloud Functions |

## Functions

| Function | Trigger | Does |
|---|---|---|
| `createUploadUrls` | Callable `{sessionId, photoBytes, cardBytes}` | Two presigned PUT URLs, 5 minutes, `image/jpeg`, the exact byte length signed in |
| `getPhotoUrls` | Callable `{keys}` | Presigned GET URLs, 1 hour, only for the caller's own keys (at most 60) |
| `stampSession` | Callable `{sessionId}` | Checks the photo and card exist, then in one transaction: server timestamp, next proof number, totals, exercise stats, week count and streak. Calling it twice returns the first stamp. Queues `analyzePhysique` when the score is on and the user is 18 or over |
| `analyzePhysique` | Task queue `{uid, sessionId}` | The private physique score. See "Physique score" below |
| `deleteSession` | Callable `{sessionId}` | Deletes both S3 objects and the document, lowers the proof count, recounts the open week and rebuilds the affected exercise stats. Proof numbers are never reused |
| `deleteAccount` | Callable | Deletes every S3 object under `users/{uid}/`, every document under `users/{uid}`, then the auth user |
| `createAgentToken` | Callable `{name, scopes, expiresInDays?}` | Makes a `pgym_pat_` token, returns it once, stores only its SHA-256 hash. 90 days by default, `null` for no expiry, at most 20 active |
| `revokeAgentToken` | Callable `{tokenId}` | Marks the caller's token revoked, effective on the next request |
| `api` | HTTP | The read-only agent API under `/v1`. See [`docs/API.md`](../docs/API.md) |
| `rollWeek` | Scheduled, hourly | Closes each user's week 6 hours after their local Monday 00:00: extends, holds with a pass week, or breaks the streak |

## Streak rules

- A week is Monday to Sunday in the user's timezone, keyed like `2026-W46`.
- A session counts for the week of the day it **started**.
- The goal is locked when a week opens. Changing `goalPerWeek` mid-week sets next week's goal.
- One pass week is earned per 4 weeks hit. A missed week spends one automatically; the streak holds but does not grow. With no pass, the streak goes to 0.
- `streakWeeks` includes the open week as soon as it is hit.

## Physique score

Design: the architecture note's "Flow: physique analysis" and the design note's "The physique score". In order:

1. **Gate, no model call:** the user exists, `physiqueConsent` is `true`, the birth year makes them certainly 18 (born in year Y counts from 1 January of Y + 19), the session is `stamped` and has no `physique` yet. Consent and age are checked again here, not only when queued. A skipped task writes nothing.
2. **Photo:** read from S3. A storage error throws, so the queue retries (3 attempts).
3. **Claim, in one transaction:** the session's one analysis, and one of 3 model calls per user per local calendar day (the user's `timezone`). The claim is written as a failure first, so a crash mid-call reads as "Scoring did not work this time." The fourth call in a day writes `refusedReason: 'daily_limit'` without a model call.
4. **Model:** the fixed prompt, the photo and the JSON schema, temperature 0.
5. **Validate:** anything that is not valid JSON with `usable` and, when usable, a finite `score` writes `refusedReason: 'failure'` and no score. A model refusal writes its reason (`no_person`, `several_people`, `face_only`, `apparent_minor`, `unreadable`).
6. **Clamp and smooth:** the score is rounded and clamped to 0 to 100 (`rawScore`), then smoothed: `(2 x new + up to 3 earlier raw scores) / (2 + n)`, so with a full window the new photo counts 40 %.
7. **Tip:** whitespace collapsed, cut to 140 characters at a word break, then dropped (score kept) if it has an exclamation mark, an emoji or a word from the copy deck's banned list.
8. **Write** `physique: {score, rawScore, tip?, model, analyzedAt}` or `{refusedReason, model?, analyzedAt}`. The log gets token counts, never the photo, the model's text or the tip.

The model ID is `PINNED_MODEL_ID` in `src/physiquePrompt.ts`. While it is `null` no model is called and every analysis writes `refusedReason: 'failure'`.

### Stability eval

```sh
export PGYM_GEMINI_API_KEY=...            # or GEMINI_API_KEY
export PGYM_GEMINI_MODEL=...              # only while PINNED_MODEL_ID is null
export PGYM_GEMINI_PRICE_INPUT_PER_M=...  # USD per 1M input tokens, paid tier
export PGYM_GEMINI_PRICE_OUTPUT_PER_M=... # USD per 1M output tokens
npm run eval -- ./eval-photos              # optional: --runs 5 --json eval-report.json
```

Scores every `.jpg`, `.jpeg`, `.png`, `.webp`, `.heic` or `.heif` in the folder 5 times, one call at a time, with the production prompt and parser and no smoothing. Prints per photo: runs scored, mean, standard deviation, min, max, range and refusals; then mean tokens and mean cost per analysis in USD. This calls the paid API; `npm test` never runs it. `eval-photos/` and `eval-*.json` are git-ignored: photos of people never go in this repo. Send photos the way the app does (JPEG, long edge 2048 px) or the token count and cost will differ.

## Configuration

Nothing secret is in this repo.

| Name | Kind | Value |
|---|---|---|
| `PGYM_S3_BUCKET` | parameter | Bucket name |
| `PGYM_S3_REGION` | parameter | Default `us-east-1` |
| `PGYM_S3_ENDPOINT` | parameter | Empty for AWS; for MinIO, for example `http://127.0.0.1:9000` |
| `PGYM_AWS_ACCESS_KEY_ID` | secret | Secret Manager in production; `.secret.local` (git-ignored) for the emulator |
| `PGYM_AWS_SECRET_ACCESS_KEY` | secret | Same |
| `PGYM_GEMINI_API_KEY` | secret | Gemini API key, paid tier. Read only by `analyzePhysique` |

Parameters go in a git-ignored `.env.pgym-local` file next to `package.json` when running the functions emulator (`npm run emulators`). The project ID is always `pgym-local` locally.
