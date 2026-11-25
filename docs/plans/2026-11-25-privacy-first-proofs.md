# Privacy-first proof implementation plan

**Date:** 2026-11-25
**Status:** Accepted owner direction, implementation in this branch

## Goal

Make proof photos and rendered proof cards local-only. PGYM's production backend records the authenticated workout and server-issued stamp, but never retains image bytes, image URLs, or AI output.

## Data flow

1. The in-app camera captures a photo. The app normalizes it to a metadata-free JPEG and stores the working file in its protected Application Support directory.
2. The app computes SHA-256 over those exact normalized bytes.
3. If an eligible adult explicitly enabled AI analysis, the app resizes and compresses the photo below the callable limit and sends those bytes once to an authenticated, App Check-protected callable. The callable checks consent, age, and rate limits, calls the configured Gemini multimodal Flash model in memory, validates one structured positive training insight, returns it, and persists or logs neither bytes nor insight. Failure is non-blocking.
4. The app requests a stamp with session ID, photo hash, card format version, filter, and the fact that it will create a proof image. It sends no image bytes.
5. In a Firestore transaction the server verifies the synced session, hash and metadata, assigns the timestamp and monotonically increasing proof number, updates weekly streak and structured workout aggregates, and records only the hash and card metadata.
6. The app renders the final card locally from the captured photo, server receipt, workout summary, and optional local insight.
7. With `Keep proof cards on this iPhone` enabled, the card is written to protected Application Support. Otherwise it remains temporary for the completion/share flow and is removed afterward. Optional Photos auto-save requests add-only permission when saving.
8. After analysis and rendering finish, the original is deleted by default. If the user disables deletion, it remains only in protected local storage.

## Stored data

The server may store structured account, session, exercise and streak data; the server timestamp and proof number; normalized JPEG SHA-256; card format/version and filter; and whether the app reported creating a proof image. It stores no proof image bytes, image URL, storage key, AI insight, score, or analysis history.

The phone may store the normalized original when requested, locally rendered cards when requested, and an optional returned insight associated with the local session/card. Local files use complete-until-first-authentication file protection. A reinstall, device change, or local deletion makes old cards unavailable while structured workout history continues to sync.

## Trust boundary and trade-offs

The SHA-256 value binds the server record to the exact local JPEG bytes later presented by the user. It detects byte changes. It does not prove what the image depicts, when it was captured, who appears in it, or that the client honestly used the in-app camera. Server-issued time and proof numbers prevent client clock and numbering changes, not semantic photo fraud.

Local-only media removes PGYM's server-retention and signed-link exposure, but removes cross-device card recovery. Photos auto-save makes a user-directed copy governed by the user's Photos/iCloud settings. Optional AI analysis is the sole photo transmission: Google receives one reduced image for transient inference under its terms, and PGYM does not retain it.

## Test-first sequence

1. Replace backend tests that expect S3 objects or stored physique scores with contract tests for stamp metadata validation, no media dependency, transient analysis controls, structured-output validation, rate limiting, and no persistence.
2. Implement the callable and stamp transaction, then remove production S3 and physique persistence paths and photo agent scope/routes.
3. Add iOS tests for preference defaults, hashing, protected retention, temporary cleanup, original deletion timing, optional-analysis success/failure, and card insight inclusion. Implement the local proof pipeline and settings UI.
4. Update agent API, account/photo deletion behavior, privacy manifest, landing/release/support/legal copy and documentation.
5. Run backend lint/build/unit/emulator checks, web lint/build/tests, and available iOS unit/UI builds. Record exact output and any live-device/service gaps.

## Compatibility

No broad migration runs. Reads tolerate legacy prelaunch fields but new writes never create them. Account/session deletion may best-effort delete known legacy remote keys through an isolated compatibility implementation if retained; active proof creation and reads never depend on remote media.
