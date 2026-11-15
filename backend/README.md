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

`npm run test:unit` runs only the tests that need no emulator (the streak table, S3 presigning and the OpenAPI document).

No test calls AWS or any paid API: the functions take a `PhotoStore`, and the tests pass an in-memory fake.

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
| `src/index.ts` | The exported Cloud Functions |

## Functions

| Function | Trigger | Does |
|---|---|---|
| `createUploadUrls` | Callable `{sessionId, photoBytes, cardBytes}` | Two presigned PUT URLs, 5 minutes, `image/jpeg`, the exact byte length signed in |
| `getPhotoUrls` | Callable `{keys}` | Presigned GET URLs, 1 hour, only for the caller's own keys (at most 60) |
| `stampSession` | Callable `{sessionId}` | Checks the photo and card exist, then in one transaction: server timestamp, next proof number, totals, exercise stats, week count and streak. Calling it twice returns the first stamp |
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

## Configuration

Nothing secret is in this repo.

| Name | Kind | Value |
|---|---|---|
| `PGYM_S3_BUCKET` | parameter | Bucket name |
| `PGYM_S3_REGION` | parameter | Default `us-east-1` |
| `PGYM_S3_ENDPOINT` | parameter | Empty for AWS; for MinIO, for example `http://127.0.0.1:9000` |
| `PGYM_AWS_ACCESS_KEY_ID` | secret | Secret Manager in production; `.secret.local` (git-ignored) for the emulator |
| `PGYM_AWS_SECRET_ACCESS_KEY` | secret | Same |

Parameters go in a git-ignored `.env.pgym-local` file next to `package.json` when running the functions emulator (`npm run emulators`). The project ID is always `pgym-local` locally.
