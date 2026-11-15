# PGYM TestFlight checklist

What the iOS app needs before its first TestFlight build and App Review, as of card I9 (2026-11-15).
Part 1 maps every App Review guideline quoted in the PGYM market and policy research note (fetched from
https://developer.apple.com/app-store/review/guidelines/ on 2026-11-15) to where the app meets it. Part 2
is what the build already carries. Part 3 is what only the owner can do: nothing in this repo signs,
uploads or talks to App Store Connect.

Paths are relative to the repo root. View IDs are from the PGYM app views list (A1 Welcome, F7 Delete
account, and so on).

## Part 1: App Review guidelines and where PGYM meets them

| Guideline | What it asks (quoted in the research note) | Where PGYM meets it | Status |
|---|---|---|---|
| 4.8 Login Services | An app that uses Google Sign-In for the primary account "must also offer as an equivalent option another login service" that limits data to name and email, lets the user keep their email private, and does not collect interactions for advertising | Sign in with Apple is offered on A1 next to Google and email: `ios/PGYM/Features/Auth/WelcomeScreen.swift`, nonce flow in `ios/PGYM/Core/Auth/AppleSignIn.swift`, Firebase provider in `ios/PGYM/Core/Auth/FirebaseAuth.swift`. The entitlement is in `ios/Config/PGYM.entitlements` | In code. Needs the Apple provider enabled in Firebase (Part 3) |
| 5.1.1(v) Account Sign-In | "If your app supports account creation, you must also offer account deletion within the app." | F7 Delete account, reached from F6 Privacy and data: `ios/PGYM/Features/Profile/DeleteAccountScreen.swift`, `ios/PGYM/Features/Profile/PrivacyDataScreen.swift`. Server side: `deleteAccount` in `backend/src/handlers.ts` removes S3 objects, Firestore documents and the Auth user. UI test: `ios/PGYMUITests/SignInUITests.swift` deletes an account end to end | In code and UI-tested on fakes |
| Apple account deletion support page | "Offer to delete the entire account record, along with associated personal data"; no email or phone flow; a website link only to finish | F7 deletes everything in the app with no support flow. `web/app/delete-account/` is the supplementary form for people without the app | In code. The web form's verification is an open question in the privacy policy draft |
| Apple support page, token revocation | "Apps that support Sign in with Apple should use the Sign in with Apple REST API to revoke user tokens." | `revokeAppleToken` in `ios/PGYM/Core/Auth/FirebaseAuth.swift` calls `Auth.revokeToken(withAuthorizationCode:)` before `deleteAccount` | In code. Needs the Services ID and key in Firebase (Part 3) |
| 5.1.1(i) Privacy Policies | A link to the policy "in the App Store Connect metadata field and within the app in an easily accessible manner"; the policy must cover collection, use, retention, deletion and revoking consent | In the app: A1's legal line (`ios/PGYM/Features/Auth/AuthComponents.swift`), F6 "Privacy policy" row and F8 About (`ios/PGYM/Features/Profile/PrivacyDataScreen.swift`, URLs in `ios/PGYM/Features/Profile/ProfileCopy.swift`). The page: `web/app/privacy/` | In code with placeholder URLs (`example.com`). Real domain and the metadata field are Part 3 |
| 5.1.1(i), third parties | The policy must "Confirm that any third party with whom an app shares user data ... will provide the same or equal protection" | `web/app/privacy/` names Google (Firebase, Gemini) and AWS. The Gemini terms are unverified, so the line about Google's handling stays out of the build (comment in `ios/PGYM/Features/Proof/StampCopy.swift`) | Blocked on the Gemini terms check |
| App Store Connect, privacy policy URL field | "A URL that links to your company's privacy policy. Required for iOS and macOS apps." | The page exists at `web/app/privacy/` | Part 3: paste the URL |
| 1.5 Developer Information | "Make sure your app and its Support URL include an easy way to contact you" | F8 About links Support (`ios/PGYM/Features/Profile/PrivacyDataScreen.swift`); the page is `web/app/support/` | Contact details are placeholders until the company, address and email are decided |
| App Store Connect, Support URL field | Must "lead to actual contact information (legal address, email address, telephone number)" | `web/app/support/` | Part 3: real contact details, then paste the URL |
| 5.1.2(i) Data Use and Sharing | "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so." | D10 Physique consent names "Google's Gemini model" and what is sent before anything is sent: `ios/PGYM/Features/Proof/PhysiqueConsentScreen.swift`, copy in `ios/PGYM/Features/Proof/StampCopy.swift`. The score is off by default; the server skips analysis without consent: `backend/src/physique.ts` (`no_consent`) and `backend/src/handlers.ts` (`stampSession` queues analysis only with consent and age) | In code |
| 1.4.1 Medical | "Apps must clearly disclose data and methodology to support accuracy claims relating to health measurements"; "remind users to check with a doctor" | The score is worded as an AI estimate of visible muscle, never a body-fat or health measure (D10 copy in `ios/PGYM/Features/Proof/StampCopy.swift`); D11 shows "An AI estimate from this photo. Not medical advice." under every score (`ScoreSection` in `ios/PGYM/Features/Proof/SessionCompleteScreen.swift`). The method is public: the prompt is `backend/src/physiquePrompt.ts` in this open repo | In code. Reviewer reading of a 0 to 100 score is the main review risk (Part 3, review notes) |
| 5.1.3(i) Health and Health Research | Fitness data may not go to third parties "for advertising, marketing, or other use-based data mining purposes" | No ad, analytics or crash SDK in the app: dependencies in `ios/PGYM.xcodeproj/project.pbxproj` are Firebase Core, Auth, Firestore, Functions, App Check and GoogleSignIn only. `ios/PGYM/Resources/PrivacyInfo.xcprivacy` declares no tracking and App Functionality as the only purpose | In code |
| 5.1.3(ii) HealthKit | Must not write false data into HealthKit or store health data in iCloud | v1 has no HealthKit capability and no iCloud entitlement (`ios/Config/PGYM.entitlements` carries Sign in with Apple only) | Not applicable in v1; revisit with Apple Health write-back |
| 5.1.4(a) Kids | Birthdate may be asked "only for the purpose of complying with these statutes", with useful functionality "regardless of a person's age" | A5 asks the year only (`ios/PGYM/Features/Auth/YearOfBirthScreen.swift`); under 18 gets the whole log, camera and card, and only the score is locked (`PhysiqueRules.isAdult` in `ios/PGYM/Core/Physique/Physique.swift`, `isAdult` in `backend/src/physique.ts`) | In code. `AgePolicy.minimumAge` (13) in `ios/PGYM/Core/Auth/AuthModels.swift` is a placeholder for the open minimum-age decision |
| 1.3 Kids Category | "Kids Category apps may not send personally identifiable information or device information to third parties." | PGYM must not be listed in the Kids Category. Primary category is Health and Fitness (`LSApplicationCategoryType` in `ios/PGYM.xcodeproj/project.pbxproj`) | Part 3: pick the category, not Kids |
| App Store Connect, age rating | "The age rating of your app for the purpose of parental controls. ... This property is required." | Depends on the minimum age; A5 enforces whatever `AgePolicy.minimumAge` says | Part 3, after the minimum-age decision |
| 1.2 User-Generated Content | Filtering, reporting and blocking for user-generated content, including "AI content creation apps" | v1 has no feed and no public pages: a card is shared only through the iOS share sheet by its owner (D12, `ios/PGYM/Features/Proof/ProofShare.swift`). The score is private (D11 only) | Not applicable in v1. The v1.1 public `/proof/[id]` page will need report and block |
| 1.1 Objectionable content, and no rule on AI body analysis | "Apps should not include content that is offensive, insensitive, upsetting ... or just plain creepy." | The score is private, opt-in, 18+, never on the card (`ProofCardModel.swift` has no score field: `ios/PGYM/Features/Proof/ProofCardModel.swift`) and never in the agent API without `read:photos` and consent on (`backend/src/api.ts`) | In code. Explain this in the review notes (Part 3) |
| 2.5.13 (cited as the nearest text, facial recognition) | The research note found no rule on rating bodies; 2.5.13 covers facial recognition for authentication | PGYM does no face recognition and does not use the photo to sign in | Not applicable |

App-specific rules from the repo's AGENTS.md that review may also touch:

| Rule | Where |
|---|---|
| The proof photo comes from the in-app camera only, no library import | D7 `ios/PGYM/Features/Proof/ProofCameraScreen.swift` and `ProofCamera.swift`. Photos access is add-only for Save to Photos (`ProofPhotoSaver` in `ProofShare.swift`). The UI-test camera stand-in (`ios/PGYM/Features/Proof/UITestCamera.swift`) compiles only into Debug builds; an archive cannot enable it |
| The photo carries no location | `ios/PGYM/Features/Proof/ProofImageIO.swift` writes JPEGs with no metadata at all |
| Server time and proof number | `stampSession` in `backend/src/handlers.ts`; the phone shows PENDING until then (D9 in `SessionCompleteScreen.swift`) |

## Part 2: what the build carries (card I9)

| Item | Where | Notes |
|---|---|---|
| Privacy manifest | `ios/PGYM/Resources/PrivacyInfo.xcprivacy` | No tracking, no tracking domains. Collected, all linked and App Functionality: email, name, fitness, photos, other user content, user ID, other data (year of birth, timezone, units, reminder time, consent flag). Required-reason APIs: UserDefaults `CA92.1`, file timestamp `C617.1` (`attributesOfItem` for proof file sizes). Firebase and GoogleSignIn ship their own manifests in their packages |
| Camera purpose string | `NSCameraUsageDescription` in `ios/PGYM.xcodeproj/project.pbxproj`: "PGYM uses the camera to take the photo on your proof card." | Matches the copy deck, D6 |
| Photos purpose string | `NSPhotoLibraryAddUsageDescription`: "PGYM saves your proof card to Photos when you ask." | Add-only; matches the copy deck, D12 |
| Notifications | No Info.plist key exists for local notifications: iOS shows its own prompt text. The reason is on B3 Reminders before the prompt (`ios/PGYM/Features/Onboarding/RemindersScreen.swift`) | Reminders are local; no push, no APNs entitlement |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` | The app uses only HTTPS and Apple's own crypto. Confirm the answer in App Store Connect |
| App icon | `ios/PGYM/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, drawn by `ios/Tools/make-app-icon.py` from the final logo geometry | 1024 x 1024, full-bleed Ink, no alpha, no baked corners. Dark and tinted variants not built (logo spec open question 2) |
| Launch screen | `UILaunchScreen` in `ios/Config/Info.plist`: `LaunchBackground` (Ink) and `LaunchMark` (the mark at 88 pt) | Same mark and size as the in-app launch view, so there is no flash |
| Accessibility | VoiceOver labels and identifiers on every control on C1, D2, D7, D8, D11; Dynamic Type to Accessibility XXXL on C1, D2, D8, D11 | `ios/PGYMUITests/ProofFlowUITests.swift` walks faked sign-in to a stamped proof and checks the labels |
| Version | `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1` | Bump the build number for every upload |
| Bundle ID | `com.example.pgym` placeholder | Part 3 |

Commands (run on a Mac with Xcode 26; none of them signs or uploads):

```sh
cd ios
xcodebuild -scheme PGYM -destination 'platform=iOS Simulator,name=iPhone 16' build test
xcodebuild archive -scheme PGYM -destination 'generic/platform=iOS' \
  -archivePath build/PGYM.xcarchive CODE_SIGNING_ALLOWED=NO
```

## Part 3: only Konrad can do these

Signing and the record:

- [ ] Join or confirm the Apple Developer Program team, then set `DEVELOPMENT_TEAM` for the PGYM target in Xcode (Signing and Capabilities). Keep it out of git if the repo stays public; a `Local.xcconfig` works.
- [ ] Register the real bundle ID (replacing `com.example.pgym`) with the Sign in with Apple and App Attest capabilities. App Check uses App Attest on devices.
- [ ] Create the App Store Connect record: name "PGYM: Proof of Gym" (check it is free), primary category Health and Fitness, not the Kids Category, SKU, primary language.
- [ ] Put the real `GoogleService-Info.plist` in `ios/PGYM/Resources/` locally (never committed) and the real `PGYM_GOOGLE_REVERSED_CLIENT_ID` in `ios/Config/Local.xcconfig`.
- [ ] In Firebase: enable Apple (Services ID, key, team ID, so `revokeToken` works), Google and Email providers; register the App Attest provider for App Check.
- [ ] Replace the placeholder URLs (`https://example.com/privacy`, `/support`, `/terms`) in `ios/PGYM/Features/Profile/ProfileCopy.swift` and `ios/PGYM/Features/Auth/AuthComponents.swift` with the real domain.

Building and uploading:

- [ ] Archive with signing on (Xcode, Product, Archive, or `xcodebuild archive` without `CODE_SIGNING_ALLOWED=NO`), then Distribute App, App Store Connect, Upload.
- [ ] Answer export compliance (the build says no non-exempt encryption).
- [ ] Add internal testers in TestFlight. External testing needs Beta App Review and the beta review information below.

App Store Connect fields:

- [ ] Privacy policy URL (the `/privacy` page) and Support URL (the `/support` page, with real contact details: guideline 1.5).
- [ ] App Privacy answers: copy Part 3 of the privacy policy draft; they match `PrivacyInfo.xcprivacy`. Decide whether product events ship (row 9).
- [ ] Age rating, after the minimum-age decision (13 with the score locked until 18, or 17+).
- [ ] Screenshots and description from the App Store listing note.

Review notes (App Review Information, Notes field), to cover the AI score:

- [ ] A demo account: an email and password account on the production project, already past A5 and onboarding, with year of birth over 18, so the reviewer can see D10.
- [ ] Say where the score lives and how it is gated, in plain words. Suggested text:

  > PGYM logs gym sets and makes a timestamped proof card from one photo taken in the in-app camera. There is no photo-library import.
  >
  > An optional physique score is off by default. To see it: finish a session (log one set, Finish and take proof, Stamp it), then on the Session complete screen tap "Turn on the score". The consent screen names Google's Gemini as the model that reads the photo, and says exactly what is sent (this session's photo, nothing else). Nothing is sent before the user turns it on. It is only offered to users 18 or over, by the year of birth asked at sign-up, and the server checks the age again.
  >
  > The score is an AI estimate of visible muscle from one photo, shown only to the user, with the line "An AI estimate from this photo. Not medical advice." It is not a body-fat, body-composition or health measurement. It never appears on the share card. The prompt is public in our open-source repository.
  >
  > Turning it off (Profile, Privacy and data) deletes every stored score. Account deletion is in Profile, Privacy and data, Delete account, and removes all data and revokes Sign in with Apple.

- [ ] Contact name, phone and email for App Review.

Before external testers:

- [ ] Confirm Google's Gemini API terms on retention and training (privacy policy open question 1) and add the conditional D10 line if they allow it.
- [ ] Trademark and App Store name search for "PGYM" and the mark (logo spec open question 1).
- [ ] Run the whole loop on a real iPhone: camera, Sign in with Apple, Google, notifications, Save to Photos, VoiceOver, and the largest text size.
