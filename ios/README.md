# ios

The PGYM iPhone app. Swift, SwiftUI, iOS 17 and later, Swift Package Manager.

## Requirements

- Xcode 26 or later (the project uses folder-synchronised groups, and Firebase iOS SDK 13 needs Swift tools 6.2).
- An iOS simulator. No signing, no Apple team, no Firebase project needed to build and test.

## Build and test

```sh
cd ios
xcodebuild -scheme PGYM -destination 'platform=iOS Simulator,name=iPhone 16' build test
```

The first run resolves the Swift packages from GitHub (Firebase is large; allow a few minutes).

## Layout

| Path | Holds |
|---|---|
| `PGYM.xcodeproj` | The project. One scheme, `PGYM`, which builds the app and runs both test targets |
| `PGYM/App` | Entry point, the three-tab shell, Firebase start-up |
| `PGYM/Features` | One folder per feature: Auth, Onboarding, Today, Session, Proof, Progress, Profile, Routines (F2, F3, D3 and the B4 starter picker) |
| `PGYM/Core` | Models (SwiftData: routines, custom exercises, the catalogue, starters, sessions with their exercises and sets, per-exercise bests), SyncEngine (routines and sessions to Firestore), API, Notifications (reminders, the rest timer) |
| `PGYM/Resources` | Asset catalog and `exercise-catalogue.json` |
| `Packages/DesignSystem` | Local Swift package: colour, type, spacing and radius tokens, the bundled fonts, and the shared components |
| `PGYMTests` | Unit tests (app shell, Firebase start-up, design tokens, sign-in, catalogue and search, routines, routine sync, onboarding, reminders, sessions and the session sync queue) |
| `PGYMUITests` | UI tests: launch to the tab shell, sign-in, and Profile to Routines to editor to Add exercise |
| `Config` | Committed placeholders for files that must never be committed |

Files go into a target by being in its folder: the groups are synchronised with the file system, so there is no file list in the project to edit.

## Exercise catalogue

`PGYM/Resources/exercise-catalogue.json` ships in the app: `{version, exercises: [{id, name, muscleGroup, equipment}]}`. Names only, no descriptions. IDs are stable kebab-case slugs: sessions and routines store them, so never rename an ID; change the `name` instead. Muscle groups: `chest`, `back`, `shoulders`, `arms`, `legs`, `core`. Equipment: `barbell`, `dumbbell`, `kettlebell`, `machine`, `cable`, `bodyweight`, `band`, `ezBar`, `smithMachine`, `trapBar`, `other`. The unit tests fail on a duplicate ID or an unknown group.

Custom exercises (made in D3) live on the phone with IDs starting `custom-`. A routine that uses one carries its name, muscle group and equipment in Firestore, and a pull recreates the custom exercise on another phone under the same ID.

## Routine sync

Routines are saved on the phone first (`needsSync`) and pushed to `users/{uid}/routines/{routineId}` by `RoutineSyncEngine` when Firebase is configured and a user is signed in; the app asks for a sync on launch, on returning to the foreground and after every edit. Deletes are kept as tombstones until Firestore has them. On a conflict the newer `updatedAt` wins. Tests use `FakeRoutineRemote`; nothing in the tests talks to Firebase. Sync runs only on the Firebase backend; with the fake auth backend (fresh clone, CI, UI tests) routines stay on the phone.

## Design system

`import DesignSystem` gives you:

- `ColorToken` and `Color.ink`, `.iron`, `.rail`, `.hairline`, `.steel`, `.bone`, `.chalk`, `.plate`, `.photo`
- `TypeRole` (`display`, `button`, `title`, `body`, `bodyMedium`, `label`, `labelBold`, `data`), `Font.pgym(_:size:)` and `.pgymText(_:)`
- `Spacing`, `Radius`, `Stroke`, `Rotation`, `ProofCardSpec`, `ProofFilter`
- Components with previews: `PrimaryButton`, `SecondaryButton`, `Stamp`, `DayRing`, `StatTile`

Values come from the PGYM design style note. Fonts (Anton, Archivo, JetBrains Mono) are bundled in the package under `Sources/DesignSystem/Resources/Fonts` with their SIL Open Font Licence texts, and registered at launch by `FontRegistry.registerAll()`.

## Firebase configuration

The app reads Firebase settings from `PGYM/Resources/GoogleService-Info.plist`. That file is **not** in git and must never be: `.gitignore` blocks it and CI scans for secrets.

- Without the file the app still builds, launches and passes its tests; Firebase stays off.
- To use Firebase, download the plist for an iOS app with bundle ID `com.example.pgym` (or your own) from the Firebase console and save it at `PGYM/Resources/GoogleService-Info.plist`. Xcode picks it up automatically.
- `Config/GoogleService-Info.example.plist` shows the keys, with empty values.
- To point the app at the local emulator suite, enable the `PGYM_EMULATOR_HOST` variable in the scheme (Edit Scheme, Run, Arguments). Auth uses port 9099, Firestore 8080, Functions 5001.

## Sign-in (card I2)

Views A1 Welcome, A2 Email sign-in, A3 Create account (A2's create mode), A4 Reset password, A5 Year of birth, and F7 Delete account. `AppRootView` is the gate: nothing past A1 to A5 shows without a signed-in user whose `users/{uid}` has a birth year.

| Piece | Where |
|---|---|
| Protocols `AuthService`, `UserRepository`, `AccountFunctions` | `PGYM/Core/Auth/AuthServices.swift` |
| Firebase implementations (Apple with nonce, Google, email; Firestore `users/{uid}`; callable `deleteAccount`) | `PGYM/Core/Auth/FirebaseAuth.swift` |
| In-memory fakes (tests, UI tests, builds without Firebase) | `PGYM/Core/Auth/FakeAuth.swift` |
| Routing: A5 on first sign-in, onboarding for a new user, tabs for a returning one, delete and sign out | `PGYM/Features/Auth/AppSession.swift` |

Which services run is decided at launch by `AppEnvironment`:

| Situation | Services |
|---|---|
| Launch argument `-pgym-ui-test` | Fakes, signed out |
| Launch argument `-pgym-ui-test-signed-in` | Fakes, a returning user signed in |
| `GoogleService-Info.plist` present | Firebase (or the emulator, with `PGYM_EMULATOR_HOST`) |
| No plist | Fakes, so every screen can be clicked through on a simulator |

To use the real providers:

1. **Google:** copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` (gitignored) and set `PGYM_GOOGLE_REVERSED_CLIENT_ID` to `REVERSED_CLIENT_ID` from your plist. `Config/Info.plist` registers it as the URL scheme.
2. **Apple:** set your team in Xcode (Signing & Capabilities). `Config/PGYM.entitlements` carries the Sign in with Apple entitlement for device builds; enable Apple as a provider in Firebase Authentication with your Services ID and key so `revokeToken` works on account deletion.
3. **Email:** enable Email/Password in Firebase Authentication. Verification and reset emails use Firebase's templates.

The minimum age (`AgePolicy.minimumAge`, 13) and the password length (`PasswordPolicy.minimumLength`, 8) are placeholders for open decisions.

## Onboarding and reminders (card I3)

Views B1 Weekly goal, B2 Gym days and time, B3 Reminders, B4 First routine, and B5 Units (the one-tap chip on B1, as `pgym-flow-spec.md` merges it). `AppSession` routes a signed-in user whose `users/{uid}` has no `goalPerWeek` to onboarding, so quitting mid-way resumes there; the answers so far are kept on the phone per step.

| Piece | Where |
|---|---|
| Weekdays, ISO week keys, the plan, "a goal change starts next Monday" (`PlanSchedule`) | `PGYM/Core/Models/TrainingPlan.swift` |
| B4's three starters, shared with the routines module (card I4; sets and reps await trainer review) | `PGYM/Core/Models/StarterRoutines.swift` |
| `ReminderPlanner`: pure function from plan, sessions and ignored count to the notifications that should be pending; all reminder copy | `PGYM/Core/Notifications/Notifications.swift` |
| `ReminderScheduler`: hands the plan to iOS, cancels a day once a session is logged, counts ignored reminders, backs off after 5 | `PGYM/Core/Notifications/ReminderScheduler.swift` |
| Screens and their view model | `PGYM/Features/Onboarding/` |

What onboarding writes to `users/{uid}` (a merge): `goalPerWeek`, `gymDays` (`["mon", "wed", "fri"]`), `reminderTime` (`"18:00"`), `units`, `timezone`. The chosen starter is copied into the phone's routines with `RoutineStore.adopt` after that write succeeds, and reaches `users/{uid}/routines/{routineId}` through the routine sync (see "Routine sync"); the onboarding draft keeps only the starter's `id`.

Reminder rules, all local:

- One reminder per gym day at the chosen time; none on rest days, none once a session (or a draft) is logged that day, none once the week's goal is reached.
- Sunday 18:00 nudge only when the week is exactly one session short, and not if Sunday is a gym day with its own reminder.
- After 5 reminders in a row go unopened, daily reminders and the nudge pause and a "New week" line goes out on Mondays at the reminder time. Opening any PGYM notification or logging a session brings the daily ones back. The back-off is planned six weeks ahead, so it also works while the app stays closed.
- Goal and gym-day changes apply from next Monday; a new time applies at once.

`TodayScreen` calls `services.reminders.sessionLogged(at:countsTowardWeek: false)` when a draft starts (card I5). For card I7: call `sessionLogged(at: startedAt)` when the session is stamped. Card I8's F4 calls `changePlan(_:)` and writes the same fields with `UserRepository.saveOnboarding`.

## Active session (card I5)

Views D1 Pick routine, D2 Active session, D4 Set detail and D5 Leave session. D3 Add exercise comes from card I4.

| Piece | Where |
|---|---|
| SwiftData models `WorkoutSession`, `SessionExercise`, `SessionSet`, `ExerciseStat` | `PGYM/Core/Models/Session.swift` |
| Every session write (pre-fill, check, copy-down, new best, rest timer, finish, discard) | `PGYM/Core/Models/SessionStore.swift` |
| Epley, totals, new-best rule (mirrors `backend/src/sessionStats.ts`) | `PGYM/Core/Models/SessionMath.swift` |
| kg and lb display, 2.5 kg and 5 lb steps | `PGYM/Core/Models/WeightUnit.swift` |
| Rest notification | `PGYM/Core/Notifications/RestTimerNotifier.swift` |
| Sync queue to `users/{uid}/sessions/{id}` | `PGYM/Core/SyncEngine/SessionSync.swift`, `FirestoreSessionRemote.swift` |
| Screens | `PGYM/Features/Session/` |

How it stays offline-first:

- Every tap is saved to SwiftData at once. Elapsed time and the rest timer are stored as instants, so a lock, the background or a kill changes nothing.
- The full-screen session is shown whenever an open draft exists (`SessionHost`), so after a kill the app opens straight back into D2.
- A session is queued while `localVersion > syncedVersion`. The queue writes the whole client part of the document under the session's own ID (`setData` with merge), marks the version it wrote, retries with back-off after a failure, and waits while offline. A stamped session and the server-only fields are never written.
- Weights are stored in kilograms. A value typed in pounds is stored as its exact kilogram equivalent and a stored value is never rewritten from its rounded display, so 100 lb stays 100 lb.
- The display unit is the `units` on the user's profile (B5, card I3), then a choice saved on the phone, then the region's default (`WeightUnit.preferred`).
- Like routine sync, the queue talks to Firestore only on the Firebase backend, for the signed-in user from `AppSession`; with the fake auth backend sessions stay queued on the phone.
- The rest notification's identifier is kept outside the reminders' `pgym.` prefix, so a reminder reschedule never removes it.

## Proof camera, card and share (card I6)

Views D6 Camera permission, D7 Proof camera, D8 Proof card editor and D12 Share. The card follows `pgym-proof-card-spec.md` (card D4) to the pixel.

| Piece | Where |
|---|---|
| `ProofCardRenderer.render(photo:summary:options:)`: pure function to a 1080 x 1350 or 1080 x 1920 `CGImage` | `PGYM/Features/Proof/ProofCardRenderer.swift` |
| The four filters as Core Image chains | `ProofFilterChain.swift` |
| Text rules: name shrink steps, timestamp, stamp lines, stat row, kg and lb | `ProofCardText.swift` |
| Card model (no score, tip or location field), sizes, stat-row choice | `ProofCardModel.swift` |
| Clean JPEGs: photo at 2048 px with orientation applied, card at 0.85; no EXIF, no GPS | `ProofImageIO.swift` |
| AVFoundation camera, front and back, unmirrored photo | `ProofCamera.swift` |
| Screens and the flow over D2 | `CameraPermissionScreen.swift`, `ProofCameraScreen.swift`, `ProofCardEditorScreen.swift`, `ProofShare.swift`, `ProofFeature.swift` |
| Files on the phone: `Application Support/Proofs/{sessionId}/photo.jpg`, `card.jpg`, `card.json` | `ProofStore.swift` |

How it fits together:

- Finish and take proof on D2 opens the flow over D2 without ending the session, so Close on D6 or D7 goes back to D2 intact. The session ends (status stays `draft`, `endedAt` set) when the card is saved; card I7 uploads `photo.jpg` and `card.jpg`, calls `stampSession`, re-renders the card with the server's number and time, and replaces the saved screen with D11.
- The photo is saved the moment the shutter fires, the card the moment Stamp it is tapped, so after a kill D2 reopens into D8 or the saved card.
- There is no photo-library import anywhere. Photos access is add-only, for Save to Photos.
- Share and Save to Photos stay disabled until the card is stamped (D4: only a stamped card is shared).
- Camera, timer, filter, size and stat row are remembered (`ProofPreferences`).

Sample cards: the tests write four when asked:

```sh
TEST_RUNNER_PGYM_SAMPLE_DIR="$PWD/../docs/proof-card-samples" \
  xcodebuild -scheme PGYM -destination 'platform=iOS Simulator,name=iPhone 16' test \
  -only-testing:PGYMTests/ProofCardTests/testWriteSampleCards
```

The test photo `PGYMTests/Fixtures/proof-test-photo.png` is synthetic (`python3 Tools/make-proof-test-photo.py`).

## Stamping, consent and Session complete (card I7)

Views D9 Stamping (the stamp's pending state on D11, as `pgym-flow-spec.md` merges it), D10 Physique consent and D11 Session complete. Stamp it on D8 ends the session and shows D11 at once in the same cover as D2; nothing waits on the network.

| Piece | Where |
|---|---|
| Typed `createUploadUrls`, `getPhotoUrls`, `stampSession` (shapes from `backend/src/handlers.ts`), error mapping | `PGYM/Core/API/API.swift` |
| Firebase callables; App Check provider (App Attest on a device, debug provider on the simulator and the emulator) | `PGYM/Core/API/FirebaseProofAPI.swift`, set up in `PGYM/App/FirebaseBootstrap.swift` |
| In-memory server and bucket for tests and builds without Firebase | `PGYM/Core/API/FakeProofAPI.swift` |
| PUT from the file to the presigned URL, with progress | `PGYM/Core/SyncEngine/ProofUploader.swift` |
| Upload, retry, URL renewal, stamp, the persisted queue | `PGYM/Core/SyncEngine/ProofStampQueue.swift` |
| Score record, Firestore listener, consent flag | `PGYM/Core/Physique/` |
| Image cache for signed photo links (memory, Caches, network; keyed by object key) | `PGYM/Core/API/SignedImageCache.swift` |
| D11 rules as a pure model (score gating, headline, stats, bests, share) | `PGYM/Features/Proof/SessionCompleteModel.swift` |
| Screens | `SessionCompleteScreen.swift` (D11 with D9), `PhysiqueConsentScreen.swift` (D10) |
| Wiring | `PGYM/App/ProofServices.swift` |

How a proof gets its number:

1. Stamp it saves `card.jpg` (PENDING, phone time) and ends the session (`status` stays `draft`, `endedAt` set). The queue is every session in that state, so it survives a kill.
2. The session sync writes the document; the stamp queue waits for that, because `createUploadUrls` needs it.
3. `createUploadUrls` with the exact byte counts, then a PUT of `photo.jpg` and `card.jpg`. Each file is tried 3 times; a 403 (expired URL) renews the URLs once.
4. `stampSession` only after both files are up. The server is idempotent per session: a retry after a kill gets the same number (`createUploadUrls` says "already stamped", the queue asks for the stamp again).
5. The answer is saved on the session (`proofNumber`, `stampedAt`, keys, the whole receipt), `status` becomes `stamped` (the sync never writes it again), the card is re-rendered with the server's number and time, and the reminders hear `sessionLogged(at: startedAt)`.

Offline the queue waits without counting a failure and runs again when the network comes back, when the session sync has written, and when the app comes to the front. Other failures back off (2, 5, 15, 30, 60 s) and then show D9's "The upload stopped" with Try again.

The physique score:

- Off by default. D10 is offered once as a row on D11, to users 18 or over (same year rule as the server's `isAdult`), never on the first proof.
- Turn on is saved on the phone at once and written to `users/{uid}.physiqueConsent` and `physiqueConsentAt`; a change made offline is sent before the next stamp, so `stampSession` queues the score.
- D11 shows the score block only when consent is on, the user is 18 or over, and the session was stamped with the score on. The score and tip arrive through a Firestore listener on the session. A refused or failed analysis shows nothing on D11 and no error.

Without Firebase (fresh clone, UI tests) a fake server in memory stamps sessions so every screen can be clicked through; no score ever arrives there.

To run against the emulator and MinIO: start the backend as in `backend/README.md`, set `PGYM_EMULATOR_HOST`, and put a `GoogleService-Info.plist` for `pgym-local` in `PGYM/Resources/`. The simulator uses the App Check debug provider; the emulator does not enforce App Check.
