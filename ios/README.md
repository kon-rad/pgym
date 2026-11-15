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
| `PGYM/Core` | Models (SwiftData: routines, custom exercises, the catalogue, starters), SyncEngine (routines to Firestore), API, Notifications |
| `PGYM/Resources` | Asset catalog and `exercise-catalogue.json` |
| `Packages/DesignSystem` | Local Swift package: colour, type, spacing and radius tokens, the bundled fonts, and the shared components |
| `PGYMTests` | Unit tests (app shell, Firebase start-up, design tokens, catalogue and search, routines, routine sync) |
| `PGYMUITests` | UI tests: launch to the tab shell; Profile to Routines to editor to Add exercise |

## Exercise catalogue

`PGYM/Resources/exercise-catalogue.json` ships in the app: `{version, exercises: [{id, name, muscleGroup, equipment}]}`. Names only, no descriptions. IDs are stable kebab-case slugs: sessions and routines store them, so never rename an ID; change the `name` instead. Muscle groups: `chest`, `back`, `shoulders`, `arms`, `legs`, `core`. Equipment: `barbell`, `dumbbell`, `kettlebell`, `machine`, `cable`, `bodyweight`, `band`, `ezBar`, `smithMachine`, `trapBar`, `other`. The unit tests fail on a duplicate ID or an unknown group.

Custom exercises (made in D3) live on the phone with IDs starting `custom-`. A routine that uses one carries its name, muscle group and equipment in Firestore, and a pull recreates the custom exercise on another phone under the same ID.

## Routine sync

Routines are saved on the phone first (`needsSync`) and pushed to `users/{uid}/routines/{routineId}` by `RoutineSyncEngine` when Firebase is configured and a user is signed in; the app asks for a sync on launch, on returning to the foreground and after every edit. Deletes are kept as tombstones until Firestore has them. On a conflict the newer `updatedAt` wins. Tests use `FakeRoutineRemote`; nothing in the tests talks to Firebase.
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

Google Sign-In also needs the `REVERSED_CLIENT_ID` as a URL scheme; that is wired up with sign-in (card I2).
