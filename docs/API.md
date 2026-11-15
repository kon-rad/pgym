# PGYM agent API (v1)

A read-only HTTP API that lets one PGYM user's own AI agent (Claude, a script, anything that sends HTTP) read that user's data. Nothing in it gives one user access to another user's data.

- Base URL: `https://[API-DOMAIN]/v1`
- Machine-readable description: `GET /v1/openapi.json` (OpenAPI 3.1, no token needed). It is generated from the same zod schemas the handlers validate with (`backend/src/apiSchemas.ts`), so if this page and that document differ, the document wins.
- Code: `backend/src/api.ts` (the endpoints), `backend/src/agentTokens.ts` (tokens).

## Tokens

The owner creates a personal access token in the app (Profile, Agent access, view F9). The app calls the `createAgentToken` callable function:

```json
{ "name": "Claude on my laptop", "scopes": ["read:stats", "read:sessions"], "expiresInDays": 90 }
```

| Field | Rule |
|---|---|
| `name` | 1 to 60 characters |
| `scopes` | At least one of `read:profile`, `read:sessions`, `read:stats`, `read:photos` |
| `expiresInDays` | 1 to 365. Omit it for the default of 90 days; send `null` for no expiry |

The answer carries the token once: `pgym_pat_` followed by 40 letters and digits. The server keeps only its SHA-256 hash, the first 17 characters for display (`pgym_pat_` plus 8), the scopes and the dates, in `users/{uid}/agentTokens/{tokenId}`. It cannot show the token again. A user can hold at most 20 active tokens.

`revokeAgentToken` with `{ "tokenId": "..." }` revokes a token. It takes effect on the next request.

Send the token on every request:

```
Authorization: Bearer pgym_pat_...
```

Keep it in an environment variable (the examples use `PGYM_TOKEN`), never in a URL, a file you commit, or a chat.

## Scopes

| Scope | Lets the agent read |
|---|---|
| `read:profile` | Display name, units, time zone, weekly goal, gym days |
| `read:stats` | Streak, longest streak, pass weeks, proof count, this week against the goal, total weight lifted |
| `read:sessions` | Session list, every set in a session, one exercise's history |
| `read:photos` | A 10-minute link to a session's card image, and the physique score and tip inside a session (only when the owner has the score turned on) |

There is no write scope in v1.

## Conventions

| Item | Value |
|---|---|
| Format | JSON, UTF-8 |
| Weights | Kilograms (`weightKg`, `totalVolumeKg`). `units` from `/v1/me` is for display |
| Times | ISO 8601 in UTC, plus the session's IANA `timezone` |
| Query dates | `from` and `to` as `YYYY-MM-DD`, read in the owner's time zone, both inclusive |
| Pages | 50 items. When `nextCursor` is not `null`, send it back as `cursor` |
| Rate limit | 60 requests a minute per token. Every answer carries `X-RateLimit-Limit` and `X-RateLimit-Remaining`; a `429` carries `Retry-After` in seconds |
| Sessions listed | `finished` and `stamped`. Drafts are never returned. Only `stamped` sessions count toward the week |

## Endpoints

All six are `GET`. The values in the examples are made up.

### GET /v1/me

Scope `read:profile`.

```bash
curl -s https://[API-DOMAIN]/v1/me \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "displayName": "Sam",
  "units": "kg",
  "timezone": "Europe/London",
  "goalPerWeek": 4,
  "gymDays": ["mon", "tue", "thu", "sat"]
}
```

`goalPerWeek` is this week's goal; a change the owner makes applies from the next Monday.

### GET /v1/stats

Scope `read:stats`.

```bash
curl -s https://[API-DOMAIN]/v1/stats \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "streakWeeks": 7,
  "longestStreak": 9,
  "passWeeks": 1,
  "proofCount": 42,
  "thisWeek": { "weekKey": "2026-W46", "sessions": 3, "goal": 4 },
  "totalVolumeKg": 81240
}
```

### GET /v1/sessions

Scope `read:sessions`. Query: `from`, `to`, `cursor`, all optional. Newest first.

```bash
curl -s "https://[API-DOMAIN]/v1/sessions?from=2026-11-09&to=2026-11-15" \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "sessions": [
    {
      "id": "kq3V9xQb2LmT0aZp7RcW",
      "status": "stamped",
      "routineName": "Push A",
      "startedAt": "2026-11-15T17:55:04.000Z",
      "durationSec": 3120,
      "timezone": "Europe/London",
      "weekKey": "2026-W46",
      "setCount": 7,
      "totalVolumeKg": 2155,
      "proofNumber": 42
    }
  ],
  "nextCursor": null
}
```

Next page:

```bash
curl -s "https://[API-DOMAIN]/v1/sessions?cursor=$NEXT_CURSOR" \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

### GET /v1/sessions/{id}

Scope `read:sessions`. One session with every set.

```bash
curl -s https://[API-DOMAIN]/v1/sessions/kq3V9xQb2LmT0aZp7RcW \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "id": "kq3V9xQb2LmT0aZp7RcW",
  "status": "stamped",
  "routineId": "push-a",
  "routineName": "Push A",
  "startedAt": "2026-11-15T17:55:04.000Z",
  "endedAt": "2026-11-15T18:47:04.000Z",
  "stampedAt": "2026-11-15T18:47:12.000Z",
  "durationSec": 3120,
  "timezone": "Europe/London",
  "weekKey": "2026-W46",
  "proofNumber": 42,
  "exercises": [
    {
      "exerciseId": "bench-press",
      "name": "Bench press",
      "sets": [
        { "n": 1, "type": "warmup", "weightKg": 40, "reps": 10, "done": true, "rpe": null },
        { "n": 2, "type": "working", "weightKg": 80, "reps": 5, "done": true, "rpe": 8 }
      ]
    }
  ],
  "setCount": 7,
  "totalVolumeKg": 2155,
  "newBests": ["bench-press"]
}
```

The physique score is private. The response has `"physique": { "score": 61, "tip": "...", "analyzedAt": "..." }` (or `{ "refusedReason": "..." }` when the photo could not be scored) only when the token has `read:photos` **and** the owner has the score turned on. Otherwise the field is absent.

### GET /v1/exercises/{id}/history

Scope `read:sessions`. Every done set of one exercise across stamped sessions, newest first, with the best set and the estimated one-rep max (Epley: weight x (1 + reps / 30)) per session. Takes `from`, `to` and `cursor` like the session list. A page can hold fewer than 50 entries while `nextCursor` is not `null`; keep paging until it is.

```bash
curl -s https://[API-DOMAIN]/v1/exercises/bench-press/history \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "exerciseId": "bench-press",
  "name": "Bench press",
  "bestSet": { "weightKg": 80, "reps": 5 },
  "bestE1rmKg": 93.3,
  "lastPerformedAt": "2026-11-15T17:55:04.000Z",
  "history": [
    {
      "sessionId": "kq3V9xQb2LmT0aZp7RcW",
      "startedAt": "2026-11-15T17:55:04.000Z",
      "e1rmKg": 93.3,
      "sets": [
        { "type": "warmup", "weightKg": 40, "reps": 10 },
        { "type": "working", "weightKg": 80, "reps": 5 }
      ]
    }
  ],
  "nextCursor": null
}
```

### GET /v1/sessions/{id}/card

Scope `read:photos`. A signed link to the card image of a stamped session, valid 10 minutes.

```bash
curl -s https://[API-DOMAIN]/v1/sessions/kq3V9xQb2LmT0aZp7RcW/card \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "url": "https://[signed-storage-link]",
  "expiresAt": "2026-11-15T19:10:00.000Z"
}
```

### GET /v1/openapi.json

No token.

```bash
curl -s https://[API-DOMAIN]/v1/openapi.json
```

## Errors

Every error has the same body. Branch on `code`, which is stable; `message` is for people.

```json
{
  "error": {
    "code": "insufficient_scope",
    "message": "This token does not have read:photos.",
    "requiredScope": "read:photos"
  }
}
```

| Status | `code` | When |
|---|---|---|
| 400 | `invalid_request` | A bad date, cursor or ID |
| 401 | `invalid_token` | The token is missing, malformed, unknown, revoked or expired |
| 403 | `insufficient_scope` | The token lacks the endpoint's scope (named in `requiredScope`) |
| 404 | `not_found` | No such endpoint, or no such session or exercise for this owner. Another user's session is always a 404 |
| 405 | `method_not_allowed` | Anything but `GET`. The API is read-only |
| 429 | `rate_limited` | More than 60 requests in a minute on this token; wait `Retry-After` seconds |
| 500 | `server_error` | Our fault; retry once after a short wait |

Order of checks: route, token (401), rate limit (429), scope (403), parameters (400), data (404).

## Running it locally

The `api` function runs in the Functions emulator (`npm run emulators` in `backend/`). Its local base URL is:

```
http://127.0.0.1:5571/pgym-local/us-central1/api/v1
```

```bash
curl -s http://127.0.0.1:5571/pgym-local/us-central1/api/v1/me \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

Create a token for a test user by calling `createAgentToken` against the emulator from the app, or from a test as `backend/test/api.test.ts` does.
