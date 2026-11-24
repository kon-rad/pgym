# PGYM

Your gym photos stay on your phone.

Proof photos are captured in-app, normalized and hashed locally. The server issues the timestamp and proof number and stores the SHA-256 binding plus card metadata, never photo or card bytes. Optional AI analysis is off by default; when enabled for an eligible adult, the selected reduced photo is sent once to Google Gemini for transient analysis and is not retained by PGYM. The returned training insight stays local.

Proof of gym. Log a session, take one photo in the gym, get one timestamped proof card to share.

Status: early build. Nothing here is released yet.

## What is in this repo

| Folder | Holds |
|---|---|
| `ios/` | The iPhone app. Swift and SwiftUI, iOS 17 and later, SwiftData for offline-first logging |
| `backend/` | Firebase Cloud Functions (TypeScript), Firestore rules, and the read-only agent API under `/v1` |
| `web/` | The Next.js landing site, including the guide, the blog, the page for agents and `/skill.md` |

## How it works

1. You log sets during a session.
2. You take one photo with the in-app camera when you finish.
3. The server stamps the session with the time and a proof number, and the app renders a card you can share.

Sign-in is Firebase Authentication (Apple, Google, or email and password). Photos are stored in a private AWS S3 bucket and are only reachable through short-lived signed URLs.

## Agent access

PGYM is agent-first: you can create a personal access token in the app and give it to your own AI agent. The token is read-only and scoped (`read:profile`, `read:sessions`, `read:stats`, `read:photos`). An agent can read your sessions, streak and lifts; it cannot create a proof.

## Running locally

The whole stack is meant to run on one machine with no cloud account: the Firebase emulator, a local S3 stand-in (MinIO) and a fake vision client. Each folder's README says how once its first code lands.

## Rules for contributors, human or agent

See `AGENTS.md`. The short version: no secrets in the repo, placeholders for anything account-specific, and every change runs against the local stack.

## Licence

MIT. See `LICENSE`.
