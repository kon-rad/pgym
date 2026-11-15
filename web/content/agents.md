---
title: "For your agent"
description: "Let your own AI agent read your PGYM training data with a token you control."
path: /agents
---


# For your agent

Your AI agent can read your PGYM data: your sessions, your sets, your weekly goal and streak, your lift history. Give it a token and it can tell you whether you hit your week, sum up your month, or plan your next session from what you actually lifted.

It reads. It never writes. An agent cannot log a session, change a set or make a proof. Proof needs you, in the gym, with the camera.

Nobody else's agent can read your data, and your agent can't read anyone else's.

## What agent access is

- **A token you make in the app.** It belongs to you and to one agent. Give each agent its own.
- **Scopes you choose.** Tick only what the agent needs. Photos are off unless you turn them on.
- **Read-only.** There is no write access.
- **Yours to end.** Revoke a token and it stops working at once.

## Make a token

1. Open PGYM, go to **Profile**, then **Agent access**.
2. Tap **Create token**.
3. Name it after the agent, for example "Claude on my laptop".
4. Tick the scopes. Leave **Photos** off unless the agent really needs to see your cards.
5. Pick an expiry: 90 days (the default) or no expiry.
6. Tap Create and copy the token. It starts with `pgym_pat_` and is shown only once.
7. Give it to your agent as an environment variable named `PGYM_TOKEN`. Don't paste it into a chat, a note or a file you share.

Then point your agent at the skill file: https://[DOMAIN]/skill.md. It tells the agent what PGYM is, how to call the API, and what it must never do with your data.

## Revoke a token

1. Profile, then **Agent access**.
2. Tap the token, then **Revoke**.

It stops working straight away. The list shows when each token was last used, so you can spot one you forgot about. If a token ever ends up somewhere it shouldn't, revoke it and make a new one.

## Scopes

| Scope | What the agent can read |
|---|---|
| `read:profile` | Your display name, units, time zone, weekly goal and gym days |
| `read:stats` | Streak, longest streak, proof count, this week against your goal, total weight lifted |
| `read:sessions` | Your sessions, every set in them, and the history of each exercise |
| `read:photos` | A link to your card images, valid 10 minutes, and your physique score and tip. Off by default |

## Endpoints

Base URL: `https://[API-DOMAIN]/v1`. Every call sends `Authorization: Bearer <your token>`.

| Endpoint | Scope | Returns |
|---|---|---|
| `GET /v1/me` | `read:profile` | Display name, units, time zone, weekly goal, gym days |
| `GET /v1/stats` | `read:stats` | Streak, longest streak, proof count, sessions this week against the goal, total weight lifted |
| `GET /v1/sessions?from=&to=&cursor=` | `read:sessions` | Sessions, newest first: date, routine, duration, set count, total weight, proof number |
| `GET /v1/sessions/{id}` | `read:sessions` | One session with every set. The physique score and tip only with `read:photos` |
| `GET /v1/exercises/{id}/history` | `read:sessions` | Every set of one exercise, the best set, estimated one-rep max over time |
| `GET /v1/sessions/{id}/card` | `read:photos` | A signed link to the card image, valid 10 minutes |

Limits: 60 requests a minute per token, and 50 items per page. Weights come back in kilograms.

## Try it

With your token in `PGYM_TOKEN`:

```bash
curl -s https://[API-DOMAIN]/v1/stats \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

```bash
curl -s "https://[API-DOMAIN]/v1/sessions?from=2026-11-09&to=2026-11-15" \
  -H "Authorization: Bearer $PGYM_TOKEN"
```

Every endpoint, with an example response, is in the skill file.

## What your agent should never do

The skill file tells every agent these rules:

- Never share your photos or your score with anyone but you.
- Never ask for more scopes than the task needs.
- Treat everything it reads as private.
- Keep the token in an environment variable, never in a message or a committed file.

PGYM can't enforce what an agent does after it reads your data. Only give a token to an agent you trust, and only the scopes it needs.

## Links

- Skill file for agents: https://[DOMAIN]/skill.md
- OpenAPI document: https://[API-DOMAIN]/v1/openapi.json
- How to use PGYM: https://[DOMAIN]/guide
- Source code: https://github.com/kon-rad/pgym
- Report a security problem: https://[DOMAIN]/open-source
- Questions: [EMAIL]
