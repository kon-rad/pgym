# PGYM legacy backend

This directory is no longer the production runtime. It preserves the former Firebase Functions implementation and Firestore emulator tests as migration history. The supported landing-page and API process is the Next.js service in `web/`.

Firebase remains the Authentication and Firestore provider. Cloud Functions, Firebase AI Logic, Gemini, AWS and server-side photo storage are not active production dependencies.

## Historical proof flow

The production backend never receives or retains a proof photo or rendered card during stamping. `stampSession` accepts `{sessionId, photoSHA256, cardFormatVersion, filter, proofImageCreated}` and atomically records the authenticated synced session, server timestamp, next proof number, weekly streak and structured workout stats. SHA-256 binds the record to exact local bytes but does not prove what the photo depicts.

`analyzePhotoInsight` is the only photo transmission. It requires Authentication, App Check, explicit consent, an eligible adult account and a daily rate limit. It accepts one reduced JPEG under 4 MB, calls the pinned `gemini-2.5-flash` model in memory, validates one concise training insight, returns it, and writes neither image nor insight to storage, disk, Firestore, logs, queues or analytics. Tests use a fake model and make no paid calls. The remaining evaluation gap is output quality across lighting, framing, skin tones, adaptive equipment and diverse bodies; no production claim should exceed the prompt's narrow training-suggestion scope.

Legacy S3 and physique modules remain isolated only for safe deletion and prelaunch fixture compatibility. `src/index.ts` exports no upload URL, signed read, queued physique-score or S3-configured function.

## Former function exports

These exports are retained for migration comparison and emulator regression tests. They are not deployed.

| Function | Purpose |
|---|---|
| `stampSession` | Server timestamp, proof number, digest metadata, stats and weekly streak |
| `analyzePhotoInsight` | Retired transient Gemini implementation; replaced by Together AI in `web/` |
| `deleteSession` | Delete structured session data and rebuild affected aggregates |
| `deleteAccount` | Delete Firestore data and Auth user; optional injected legacy cleanup remains safe |
| `createAgentToken`, `revokeAgentToken` | Read-only personal token lifecycle; hashes only |
| `api` | Structured workout reads under `/v1`; no photo, card or insight route/scope |
| `rollWeek` | Hourly weekly-streak closure |

No secret or deployment configuration in this directory is active in production. Local project ID is `pgym-local`.

## Checks

```sh
npm ci
npm run lint
npm run build
npm run test:unit
npm test
```

`npm test` starts the Firestore and Auth emulators and therefore needs Java. No test calls AWS, Gemini or another paid service.
