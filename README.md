# PGYM

Your gym photos stay on your phone.

Proof photos are captured in-app, normalized and hashed locally. The server issues the timestamp and proof number and stores the SHA-256 binding plus card metadata, never photo or card bytes. Optional AI analysis sends one reduced JPEG to an open-source vision model hosted by Together AI for transient inference. PGYM does not persist the JPEG or insight.

Proof of gym. Log a session, take one photo in the gym, get one timestamped proof card to share.

Status: early build. Nothing here is released yet.

## What is in this repo

| Folder | Holds |
|---|---|
| `ios/` | The iPhone app. Swift and SwiftUI, iOS 17 and later, SwiftData for offline-first logging |
| `backend/` | Retired Firebase Functions implementation and emulator-era tests kept as migration history |
| `web/` | The single production Next.js landing-page and API service, including authenticated operations and `/v1` |

## How it works

1. You log sets during a session.
2. You take one photo with the in-app camera when you finish.
3. The server stamps the session with the time and a proof number, and the app renders a card you can share.

Sign-in is Firebase Authentication (Apple, Google, or email and password). Proof media stays in protected local app storage according to the user's settings.

## Agent access

PGYM is agent-first: you can create a personal access token in the app and give it to your own AI agent. The token is read-only and scoped (`read:profile`, `read:sessions`, `read:stats`). An agent can read structured sessions, streak and lifts; it cannot read local media, local insights or create a proof.

## Running locally

The web service builds and tests without a cloud account. Production uses Firebase Authentication and Firestore only; tests use fakes and never call Together AI. See `web/README.md`.

## Rules for contributors, human or agent

See `AGENTS.md`. The short version: no secrets in the repo, placeholders for anything account-specific, and every change runs against the local stack.

## Licence

MIT. See `LICENSE`.
