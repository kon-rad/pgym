# AGENTS.md - rules for anyone working in this repo

This repo is public. Treat every commit as published.

## Never commit

- Keys, tokens, passwords, service-account JSON, `GoogleService-Info.plist`, `.env` files, signing certificates or provisioning profiles.
- Real user data, real photos of people, or anything copied from a private notes folder.
- Hostnames, email addresses, chat IDs or home-directory paths of the maintainers.

Use placeholders: `[DOMAIN]` for the site domain, `com.example.pgym` for the bundle ID, `pgym-local` for the Firebase project ID, and `.env.example` files with empty values.

## Build locally first

- `backend/` runs on the Firebase emulator suite. Storage calls go through one interface with two implementations: AWS S3 and a local S3-compatible server (MinIO).
- The vision model call goes through one interface with a real client and a fake client. Tests use the fake one. No test calls a paid API.
- `ios/` builds and tests on the iOS simulator against the emulator. No signing, no TestFlight upload, no App Store Connect call from an automated run.
- `web/` builds with `npm run build`. No deploy from an automated run.

## Layout

| Folder | Stack | Checks |
|---|---|---|
| `ios/` | Swift, SwiftUI, SwiftData, iOS 17+ | `xcodebuild test` on a simulator |
| `backend/` | TypeScript, Firebase Functions 2nd gen, Firestore | `npm run lint && npm test` against the emulator |
| `web/` | Next.js, TypeScript | `npm run lint && npm run build` |

## Product rules that code must keep

- The proof photo comes from the in-app camera only. No photo-library import.
- The timestamp and proof number are set by the server, never by the phone.
- The physique score is private, opt-in, 18+, and never appears on the share card or in the agent API unless the token has `read:photos` and the user turned the score on.
- The agent API is read-only in v1. Tokens are stored as SHA-256 hashes, never in clear text.
- The streak counts weeks, not days.

## Pull requests

One change per pull request, with the commands you ran and their real output in the description. Do not merge your own pull request.
