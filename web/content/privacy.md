---
title: "Privacy policy"
description: "What PGYM stores, what stays on your phone, and how optional photo insight works."
path: /privacy
updated: 2026-11-25
---

# PGYM privacy policy

**Draft, not reviewed by a lawyer.** Effective [EFFECTIVE DATE]. PGYM is operated by [COMPANY], [ADDRESS]. Questions: [EMAIL].

## The short version

Your proof photo and rendered card stay on your phone. PGYM stores your account and structured workout records in Firebase Authentication and Cloud Firestore. The server creates the timestamp and proof number and stores a SHA-256 binding, but never stores photo or card bytes.

Optional photo insight is off by default, available only to an eligible adult who turns it on, and never required to stamp a session. One reduced JPEG is sent through the authenticated PGYM service to an open-source vision model hosted by Together AI. PGYM holds it in memory for that request, does not write it to disk, Firestore, logs, analytics or backups, and does not persist the JPEG. A separate optional Pro analysis stores seven visual scores, three coaching sentences and one encouraging sentence in your private Firestore session. You choose whether scores appear on a share card. Together AI processes the image transmission under its own current terms.

## What we collect

- Firebase account identifier, email and display name supplied by your sign-in provider.
- Year of birth, units, timezone, weekly goal and gym days.
- Routines, exercises, sets, session times, proof number, weekly streak and aggregate training statistics.
- A lowercase SHA-256 digest and card format metadata for a stamped local proof.
- If you request Pro physique analysis: six dimension scores, an overall score, coaching, encouragement, analysis time and model version.
- Agent token name, scopes, prefix, timestamps and SHA-256 hash. The full personal token is shown once and never stored.
- Waitlist email if you submit the landing-page form.
- Operational metadata needed for security, rate limits and redacted structured logs. Request bodies, authorization values, photo bytes and model output are redacted or omitted.

We do not use advertising trackers. We do not sell personal data.

## Photos and optional AI insight

The app camera captures the proof. There is no photo-library import. The original and card follow the local retention settings you choose on the device.

For optional photo insight, the app sends one reduced JPEG up to the service limit. The existing optional workout insight returns one short training suggestion and stays on your device. The optional Pro physique analysis returns six 0-100 visual dimension estimates, a separate overall score, three coaching sentences and one encouraging sentence. It is requested from a stamped proof card and is stored in your Firestore session so you can see history and personal records. Scores cannot measure metabolic health, visceral fat, body composition, posture diagnoses or injury risk. Lighting, clothing, pose and camera distance can change them. Analysis is optional and can be wrong. Sharing scores requires you to select a score layout; the ordinary workout card excludes them. The original photo stays on your device by default for later analysis or sharing and can be deleted in Settings or Privacy and data.

## Providers and purposes

| Provider | Data | Purpose |
|---|---|---|
| Google Firebase Authentication | Account identifier and sign-in details | Sign-in and account management |
| Google Cloud Firestore | Profile and structured workout records | Sync, stamping, streaks and agent reads |
| Together AI | One reduced JPEG when the eligible user opts in | Transient open-source vision inference |
| DigitalOcean | Encrypted service traffic and redacted operational logs | Hosts the single Next.js process |

Firebase Cloud Functions, Firebase AI Logic, Gemini, AWS and server-side photo storage are not active dependencies.

## Agent access

You may create a scoped, read-only personal token for your own agent. It can read only the structured categories you authorize. The v1 API has no write or photo scope and never returns local media or local insights. Treat the token like a password and revoke it if it is exposed.

## Retention and deletion

Structured records and any stored analysis remain until you delete the analysis, session or account, subject to any legally required short-lived backups [RETENTION PERIOD TO CONFIRM]. Account deletion removes the Firebase Authentication user, Firestore user document, subcollections and agent-token hashes. Photos and cards stored only on the device must be deleted from the device or Photos app by you.

## Security and your choices

Traffic uses HTTPS. Firebase ID tokens protect app operations; personal tokens are stored as SHA-256 hashes and rate-limited. Logs are structured and redact secrets, image fields, bodies and model output.

You can keep photo analysis off, turn it off and delete stored scores, revoke any agent token, delete individual sessions, or delete your account in the app. Contact [EMAIL] for access, correction or deletion questions. Rights and response periods depend on [JURISDICTION].

## Children and medical use

The minimum account age is [MINIMUM AGE]. Optional photo insight is restricted to users 18 and over. PGYM is not a medical device and does not provide medical advice.

## Changes

Material changes will be described here and, where required, in the app before they apply. The current policy is available at [DOMAIN]/privacy.
