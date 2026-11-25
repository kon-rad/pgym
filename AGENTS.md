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

## Current phase: build everything, test at the end (owner, 2026-11-15)

The owner tests the whole product by hand once it is built. Until then:

- Write the complete feature, not a stub. Every view, function and page a task names gets real code.
- Do not stop because a simulator, Xcode, the Firebase emulator, a cloud account or a sign-in provider is missing. Run the checks that can run on the machine (type checks, lint, unit tests, `npm run build`, `swift build` or `xcodebuild build` if present). For every check that could not run, say so in the pull request under "Not verified" with the exact command to run later.
- Do not connect to a real Firebase project, AWS account or vision API. Code against the interfaces and the placeholders.
- Never report an unrun check as passing.

## Experience bar: it should make people want to come back

PGYM exists to get people to the gym and keep them healthy. The look and feel is part of the product, not decoration.

- **Make it pop.** Strong type, the orange accent used with intent, full-bleed photos, generous spacing. No default-looking lists or system-grey forms where a designed component exists.
- **Reward every finished action.** A logged set gets a haptic and a small animation; a new best gets a clear moment; stamping the proof card is the big one: stamp animation, haptic, the proof number counting up, the streak moving.
- **Positive only.** Celebrate showing up. No guilt copy, no red warnings, no "you broke your streak", no countdowns. A missed week is followed by a fresh start.
- **Motion with purpose.** Spring animations on state changes, smooth transitions between log, camera and card. Respect Reduce Motion and keep every animation under about 600 ms, except the stamp moment.
- **Fast and low friction.** Start a session in two taps, one tap per set, last weights pre-filled.
- **Accessible.** Dynamic Type, VoiceOver labels, contrast that passes: dark text on the orange accent, never light text on it.
- **The landing site follows the same bar:** a hero that shows the proof card, scroll animations that are subtle and quick, real copy from the copy notes, and a fast first load.

## Layout

| Folder | Stack | Checks |
|---|---|---|
| `ios/` | Swift, SwiftUI, SwiftData, iOS 17+ | `xcodebuild test` on a simulator |
| `backend/` | TypeScript, Firebase Functions 2nd gen, Firestore | `npm run lint && npm test` against the emulator |
| `web/` | Next.js, TypeScript | `npm run lint && npm run build` |

## Product rules that code must keep

- The proof photo comes from the in-app camera or a photo the user explicitly selects in the system photo picker. Strip metadata from either source before storage.
- The timestamp and proof number are set by the server, never by the phone.
- The physique score is private, opt-in, 18+, and never appears on the share card or in the agent API unless the token has `read:photos` and the user turned the score on.
- The agent API is read-only in v1. Tokens are stored as SHA-256 hashes, never in clear text.
- The streak counts weeks, not days.

## Pull requests

One change per pull request, with the commands you ran and their real output in the description. Do not merge your own pull request.
