---
name: pgym
description: Read your owner's PGYM gym data (sessions, sets, weekly goal and streak, lift history) through the read-only PGYM API with a personal access token. Use when your owner asks about their training, whether they hit their weekly goal, a summary of their week or month, or what to lift next session.
---


# PGYM skill

This file is for you, the AI agent. It tells you how to read your owner's PGYM data and what you must never do with it. Your owner is the one person whose token you hold.

## What PGYM is

PGYM ("proof of gym") is an iPhone app. Your owner logs gym sets, takes one photo in the app's camera at the end of a session, and gets a card with a server timestamp and a proof number. #042 means the 42nd session they proved.

Facts you need to read the data correctly:

- **The goal is sessions per week**, 2 to 6, chosen by the owner. A week that reaches the goal is "locked" and extends the streak.
- **The streak counts weeks, not days.** Rest days never break it. One pass week is earned for every 4 weeks hit and is spent automatically on a short week.
- **Weeks start on Monday in the owner's time zone.** Each session carries a `weekKey` such as `2026-W46` (ISO week).
- **Only stamped sessions count.** A session needs at least one logged set and one photo to be `stamped`. A `finished` session (saved without a photo) does not count toward the week.
- **The physique score is private.** An optional 0 to 100 AI estimate from the session photo, with one training tip. It is not medical advice.
- **The API is read-only.** You cannot create sessions, edit sets, or make a proof. Only the owner can, in the gym, with the app's camera.

## Getting a token

You cannot create a token. Your owner does, in the app:

1. Open the Profile tab, then **Agent access** (view F9).
2. Tap **Create token**. Give it a name that says which agent it is for.
3. Tick only the scopes the task needs (see Scopes below). Photos are off by default; leave them off unless the task needs them.
4. Choose an expiry: 90 days is the default, or no expiry.
5. Copy the token. It is shown once and starts with `pgym_pat_`.

Where you keep it:

- **In an environment variable, `PGYM_TOKEN`.** Read it from the environment at call time.
- **Never in a file you commit**, never in a config file inside a repo, never in a URL or query string.
- **Never in a message.** Do not repeat it back to your owner, write it to a chat, a log, an issue, a note or a memory. If your owner pastes it into the conversation, tell them to set it as `PGYM_TOKEN` in your environment and to revoke and replace it if that conversation is stored anywhere.
- If you have no token, tell your owner the steps above and name the exact scopes your task needs. Ask for nothing more.

If a call returns `401`, the token is missing, wrong, expired or revoked. Ask your owner for a new one; do not retry in a loop.

## Base URL and conventions

```
https://[API-DOMAIN]/v1
```

Every request sends the token as a bearer header:

```
Authorization: Bearer $PGYM_TOKEN
```

| Convention | Value |
|---|---|
| Format | JSON, UTF-8 |
| Weights | Always kilograms (`weightKg`, `totalVolumeKg`). Convert for display using `units` from `/v1/me`: 1 kg = 2.20462 lb |
| Times | ISO 8601 in UTC (`2026-11-15T09:47:12Z`), plus the session's IANA `timezone` |
| Dates in queries | `YYYY-MM-DD`, read in the owner's time zone, both ends inclusive |
| Total weight lifted | Weight x reps over working sets only; warm-up sets are excluded |
| Estimated one-rep max | Epley formula: weight x (1 + reps / 30) |
| Full description | OpenAPI 3.1 at `https://[API-DOMAIN]/v1/openapi.json`. If it differs from this file, the OpenAPI document wins |

## Scopes

| Scope | Lets you read | Ask for it when |
|---|---|---|
| `read:profile` | Display name, units, time zone, weekly goal, gym days | You need units or the goal |
| `read:stats` | Streak, longest streak, pass weeks, proof count, this week against the goal, total weight lifted | Weekly check-ins, "did I hit my goal" |
| `read:sessions` | Session list, every set in a session, one exercise's history | Summaries, planning, anything about lifts |
| `read:photos` | A short-lived link to a session's card image, and the physique score and tip inside a session | Only when the owner explicitly asks to see their own card or score |

There is no write scope.

## Endpoints

Six endpoints, all `GET`.

| Endpoint | Scope | Returns |
|---|---|---|
| `/v1/me` | `read:profile` | The owner's profile |
| `/v1/stats` | `read:stats` | Streak, counts, this week |
| `/v1/sessions?from=&to=&cursor=` | `read:sessions` | Sessions, newest first, 50 per page |
| `/v1/sessions/{id}` | `read:sessions` | One session with every set |
| `/v1/exercises/{id}/history` | `read:sessions` | Every set of one exercise, best set, estimated one-rep max over time |
| `/v1/sessions/{id}/card` | `read:photos` | A signed link to the card image, valid 10 minutes |

The values in the example responses below are examples, not real data.

### GET /v1/me

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

`goalPerWeek` is the goal for the current week. A change the owner makes applies from the following Monday.

### GET /v1/stats

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
  "thisWeek": {
    "weekKey": "2026-W46",
    "sessions": 3,
    "goal": 4
  },
  "totalVolumeKg": 81240
}
```

`thisWeek.sessions` counts stamped sessions only. `totalVolumeKg` is all-time.

### GET /v1/sessions

Query parameters, all optional: `from` and `to` (dates), `cursor` (from the previous page).

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
      "startedAt": "2026-11-15T17:55:04Z",
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

When `nextCursor` is not `null`, call again with `cursor=<nextCursor>` to get the next 50.

### GET /v1/sessions/{id}

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
  "startedAt": "2026-11-15T17:55:04Z",
  "endedAt": "2026-11-15T18:47:04Z",
  "stampedAt": "2026-11-15T18:47:12Z",
  "durationSec": 3120,
  "timezone": "Europe/London",
  "weekKey": "2026-W46",
  "proofNumber": 42,
  "exercises": [
    {
      "exerciseId": "bench-press",
      "name": "Bench press",
      "sets": [
        { "n": 1, "type": "warmup", "weightKg": 40, "reps": 10, "done": true },
        { "n": 2, "type": "working", "weightKg": 80, "reps": 5, "done": true },
        { "n": 3, "type": "working", "weightKg": 80, "reps": 5, "done": true },
        { "n": 4, "type": "working", "weightKg": 80, "reps": 4, "done": true }
      ]
    },
    {
      "exerciseId": "overhead-press",
      "name": "Overhead press",
      "sets": [
        { "n": 1, "type": "working", "weightKg": 45, "reps": 8, "done": true },
        { "n": 2, "type": "working", "weightKg": 45, "reps": 8, "done": true },
        { "n": 3, "type": "working", "weightKg": 45, "reps": 7, "done": true }
      ]
    }
  ],
  "setCount": 7,
  "totalVolumeKg": 2155,
  "newBests": ["bench-press"]
}
```

With `read:photos`, the response also has `"physique": { "score": 61, "tip": "...", "analyzedAt": "..." }`, or `"physique": { "refusedReason": "too_dark" }` when the photo could not be scored. Without that scope the field is absent. Do not mention the score unless your owner asked about it.

### GET /v1/exercises/{id}/history

Use an `exerciseId` from a session (for example `bench-press`). Takes `from`, `to` and `cursor` like the session list.

```bash
curl -s https://[API-DOMAIN]/v1/exercises/bench-press/history \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "exerciseId": "bench-press",
  "name": "Bench press",
  "bestSet": { "weightKg": 80, "reps": 5, "sessionId": "kq3V9xQb2LmT0aZp7RcW" },
  "bestE1rmKg": 93.3,
  "lastPerformedAt": "2026-11-15T17:55:04Z",
  "history": [
    {
      "sessionId": "kq3V9xQb2LmT0aZp7RcW",
      "startedAt": "2026-11-15T17:55:04Z",
      "e1rmKg": 93.3,
      "sets": [
        { "type": "working", "weightKg": 80, "reps": 5 },
        { "type": "working", "weightKg": 80, "reps": 5 },
        { "type": "working", "weightKg": 80, "reps": 4 }
      ]
    },
    {
      "sessionId": "Hn7cY2pQe9WbL4sKx0Ad",
      "startedAt": "2026-11-09T18:02:40Z",
      "e1rmKg": 90.4,
      "sets": [
        { "type": "working", "weightKg": 77.5, "reps": 5 },
        { "type": "working", "weightKg": 77.5, "reps": 5 },
        { "type": "working", "weightKg": 77.5, "reps": 5 }
      ]
    }
  ],
  "nextCursor": null
}
```

### GET /v1/sessions/{id}/card

Only with `read:photos`, and only when your owner asks to see their own card.

```bash
curl -s https://[API-DOMAIN]/v1/sessions/kq3V9xQb2LmT0aZp7RcW/card \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```json
{
  "url": "https://[signed-storage-link]",
  "expiresAt": "2026-11-15T19:10:00Z"
}
```

The link works for 10 minutes. Show it to your owner and nothing else: do not download, store, upload or forward the image.

## Limits

| Limit | Value |
|---|---|
| Requests | 60 a minute per token |
| Page size | 50 items |
| Token lifetime | 90 days by default, or no expiry if the owner chose it. Revocation takes effect at once |
| Card link | Valid 10 minutes |
| Write access | None |

Batch your reads. For a monthly summary, one `/v1/sessions` call with `from` and `to` beats one call per day.

## Errors

Errors return a JSON body:

```json
{
  "error": {
    "code": "insufficient_scope",
    "message": "This token does not have read:photos.",
    "requiredScope": "read:photos"
  }
}
```

| Status | `code` | What to do |
|---|---|---|
| 400 | `invalid_request` | A parameter is wrong (bad date, bad cursor). Fix it; don't retry unchanged |
| 401 | `invalid_token` | Missing, wrong, expired or revoked token. Ask the owner for a new one |
| 403 | `insufficient_scope` | Tell the owner which scope is missing (`requiredScope`) and why the task needs it. Never ask for more than that |
| 404 | `not_found` | No such session or exercise for this owner |
| 429 | `rate_limited` | Wait the number of seconds in the `Retry-After` header, then retry once |
| 500, 503 | `server_error`, `unavailable` | Retry once after a short wait; then tell the owner PGYM is not answering |

## Worked tasks

### 1. Weekly summary

Owner: "How was my week at the gym?" Scopes: `read:stats`, `read:sessions` (plus `read:profile` for units).

```bash
curl -s https://[API-DOMAIN]/v1/stats -H "Authorization: Bearer $PGYM_TOKEN"
curl -s "https://[API-DOMAIN]/v1/sessions?from=2026-11-09&to=2026-11-15" -H "Authorization: Bearer $PGYM_TOKEN"
```

1. Take `from` as this Monday and `to` as today, in the owner's time zone.
2. From `/v1/stats`: sessions this week against the goal, and the streak.
3. From the list: count `stamped` sessions, sum `totalVolumeKg`, list routines and dates.
4. For new bests, call `/v1/sessions/{id}` on each session and read `newBests`.
5. Reply in a few lines, in the owner's units. Example shape: "3 of 4 sessions this week. Streak: 7 weeks. 6,420 kg lifted. New best: bench press 80 kg x 5."

### 2. Did I hit my goal?

Owner: "Did I hit my goal this week?" Scope: `read:stats`.

```bash
curl -s https://[API-DOMAIN]/v1/stats -H "Authorization: Bearer $PGYM_TOKEN"
```

1. Compare `thisWeek.sessions` with `thisWeek.goal`.
2. If sessions >= goal: the week is locked. Say so and give the streak.
3. If not and the week is still running: say how many sessions are left and how many days remain until Sunday night in the owner's time zone. One session counts, even a short one.
4. For a past week, call `/v1/sessions` with that week's Monday and Sunday and count `stamped` sessions. The goal then may have been different from today's, since goal changes apply from the next week; if you can't tell, say so.
5. Never use guilt. State what happened: "3 of 4. One session locks the week." not "You missed your goal."

### 3. Plan my next session from my lift history

Owner: "What should I lift next time?" Scopes: `read:sessions`, `read:profile`.

```bash
curl -s https://[API-DOMAIN]/v1/me -H "Authorization: Bearer $PGYM_TOKEN"
curl -s https://[API-DOMAIN]/v1/sessions -H "Authorization: Bearer $PGYM_TOKEN"
curl -s https://[API-DOMAIN]/v1/sessions/kq3V9xQb2LmT0aZp7RcW -H "Authorization: Bearer $PGYM_TOKEN"
curl -s https://[API-DOMAIN]/v1/exercises/bench-press/history -H "Authorization: Bearer $PGYM_TOKEN"
```

1. From the latest sessions, work out which routine is next (the owner usually rotates them; if unclear, ask).
2. Open the last session of that routine to get its exercises and sets.
3. For each exercise, read its history for the last two or three times it was done.
4. Suggest a weight and reps per exercise with a simple rule, and say which rule you used. A common default: if every working set reached its reps the last two times, add the smallest step (2.5 kg or 5 lb); if not, repeat the weight; if reps fell two sessions running, drop about 10%.
5. Give the plan as a short list the owner can follow in the app. You cannot write it into PGYM; there is no write scope.
6. This is training advice, not medical advice. If the owner mentions pain or injury, tell them to see a professional and don't push weight up.

## Rules

1. **Never share the owner's photos or physique score.** Not in a message to anyone else, not in a public post, not in a file, not to another tool or service. Show them only to the owner, and only when asked.
2. **Ask for the fewest scopes the task needs.** No `read:photos` for summaries or plans. If a scope is missing, name it and say why.
3. **Treat all PGYM data as private.** Sessions, sets, times and routines show when and where someone trains. Don't store more than the task needs, don't send it to third parties, and don't put it in shared logs.
4. **Keep the token secret.** Environment variable `PGYM_TOKEN` only. Never echo, log or commit it.
5. **Read-only.** Never claim you logged a session, changed a routine or created a proof.
6. **Talk like a training partner.** Short and plain. No guilt, no body judgements, no weight-loss or diet advice drawn from this data.
7. **Stop when access ends.** On `401`, stop and ask. If the owner says to stop, delete any PGYM data you saved and tell them they can revoke the token in Agent access.

## Links

- For people: https://[DOMAIN]/agents
- OpenAPI: https://[API-DOMAIN]/v1/openapi.json
- Source code: https://github.com/kon-rad/pgym
- Security problems: https://[DOMAIN]/open-source
