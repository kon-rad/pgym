# PGYM backend

Firebase Cloud Functions 2nd gen, Firestore rules and the read-only agent API. Node 20+ is required; Java 11+ is required for emulator tests.

## Privacy-first proof flow

The production backend never receives or retains a proof photo or rendered card during stamping. `stampSession` accepts `{sessionId, photoSHA256, cardFormatVersion, filter, proofImageCreated}` and atomically records the authenticated synced session, server timestamp, next proof number, weekly streak and structured workout stats. SHA-256 binds the record to exact local bytes but does not prove what the photo depicts.

`analyzePhotoInsight` is the only photo transmission. It requires Authentication, App Check, explicit consent, an eligible adult account and a daily rate limit. It accepts one reduced JPEG under 4 MB, calls the pinned `gemini-2.5-flash` model in memory, validates one concise training insight, returns it, and writes neither image nor insight to storage, disk, Firestore, logs, queues or analytics. Tests use a fake model and make no paid calls. The remaining evaluation gap is output quality across lighting, framing, skin tones, adaptive equipment and diverse bodies; no production claim should exceed the prompt's narrow training-suggestion scope.

Legacy S3 and physique modules remain isolated only for safe deletion and prelaunch fixture compatibility. `src/index.ts` exports no upload URL, signed read, queued physique-score or S3-configured function.

## Active functions

| Function | Purpose |
|---|---|
| `stampSession` | Server timestamp, proof number, digest metadata, stats and weekly streak |
| `analyzePhotoInsight` | Optional transient Gemini inference with no result persistence |
| `deleteSession` | Delete structured session data and rebuild affected aggregates |
| `deleteAccount` | Delete Firestore data and Auth user; optional injected legacy cleanup remains safe |
| `createAgentToken`, `revokeAgentToken` | Read-only personal token lifecycle; hashes only |
| `api` | Structured workout reads under `/v1`; no photo, card or insight route/scope |
| `rollWeek` | Hourly weekly-streak closure |

Only `PGYM_GEMINI_API_KEY` is an active production secret. Local project ID is `pgym-local`.

## Checks

```sh
npm ci
npm run lint
npm run build
npm run test:unit
npm test
```

`npm test` starts the Firestore and Auth emulators and therefore needs Java. No test calls AWS, Gemini or another paid service.
