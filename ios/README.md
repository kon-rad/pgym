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
| `PGYM/Features` | One folder per feature: Auth, Onboarding, Today, Session, Proof, Progress, Profile |
| `PGYM/Core` | Models (SwiftData), SyncEngine, API, Notifications |
| `PGYM/Resources` | Asset catalog; later the exercise catalogue JSON |
| `Packages/DesignSystem` | Local Swift package: colour, type, spacing and radius tokens, the bundled fonts, and the shared components |
| `PGYMTests` | Unit tests (app shell, Firebase start-up, every design token) |
| `PGYMUITests` | UI test that launches the app to the tab shell |
| `Config` | Committed placeholders for files that must never be committed |

Files go into a target by being in its folder: the groups are synchronised with the file system, so there is no file list in the project to edit.

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
