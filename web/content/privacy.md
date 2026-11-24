---
title: "Privacy policy"
description: "What PGYM collects, where it is stored, what goes to Google's Gemini, how long it stays and how to delete it."
path: /privacy
updated: 2026-11-15
---

<!-- Copied from the vault's copy/pgym-privacy-policy-draft.md, Part 1 (the policy text), on 2026-11-15. Headings moved up one level; wikilinks written out; the repo URL filled in because kon-rad/pgym is public. Bracketed italic notes are for counsel and come out before publishing. -->

# PGYM privacy policy

**Privacy-first proof update, 25 November 2026:** Your gym photos stay on your phone. PGYM does not retain proof photos or cards on its servers. The server stores structured workout data, its timestamp and proof number, and a SHA-256 hash plus card metadata. A hash binds the record to exact bytes but does not prove what the photo depicts.

Optional AI photo analysis is off by default and limited to eligible adults. When enabled, the selected reduced photo is sent once through PGYM's authenticated, App Check-protected function to Google's Gemini API for transient analysis and is not retained by PGYM. The returned concise training insight stays local and may appear on the locally rendered card. Analysis failure never blocks stamping or sharing. Google processes the transmission under its terms.

The local controls are Keep proof cards on this iPhone, Automatically save proof cards to Photos, and Delete the photo after the card is created. Their defaults are on, off and on. A reinstall, device change or local deletion can make historical cards unavailable; structured workout history continues to sync.

Effective [EFFECTIVE DATE]. PGYM is run by [COMPANY], [ADDRESS]. Questions: [EMAIL].

PGYM is an iPhone app for logging gym sessions. You log your sets, take one photo in the app, and get a card with the date, the time and a proof number. If you choose, an AI model reads the photo and gives you a private score and one training tip. This policy says what PGYM collects, why, where it is stored, who else handles it, how long it stays and how you delete it.

The PGYM code is open source. You can read how the app stores data, the database security rules and the exact prompt sent to the AI model at https://github.com/kon-rad/pgym.

## What we collect

**When you create an account**

- Your email address and, if your sign-in provider gives one, your name. These come from Sign in with Apple, Google Sign-In, or the email and password you type. If you use Sign in with Apple and choose to hide your email, we get Apple's relay address, not your real one.
- Your year of birth. Apple and Google do not give us your age, so the app asks. We use it to apply the age rules below. We do not ask for your full date of birth.
- An account ID that our sign-in service creates.

**When you set up the app**

- Your weekly goal (sessions per week), the days you plan to train, the time you want a reminder, your units (kg or lb) and your time zone. The time zone decides which week a session counts toward.
- Your routines: their names, order, exercises and target sets and reps.

**When you train**

- Each session: the routine, start and end time, duration, time zone, every exercise and set (weight, reps, set type, whether it was done, and an effort rating if you add one), the totals, and any new personal bests.
- Per exercise: your best weight, best set, estimated one-rep max, when you last did it and how many sessions included it.
- Your streak, longest streak, pass weeks and proof count. Our server works these out.

**When you take a proof**

- The photo you take in the PGYM camera, and the card image the app makes from it. The app removes location data from the photo on your phone before it is uploaded. Photos can only be taken in the app; PGYM does not read your photo library.
- The filter and card size you picked, the proof number and the time our server received the proof.

**If you turn on the physique score**

- That you agreed, and when.
- For each analysed session: the score (0 to 100), the tip, the name of the AI model used, when it ran, and, if the photo could not be scored, the reason code.

**If you create an agent token**

- The token's name, its permissions (scopes), when it was created, last used, when it expires and whether you revoked it. We store a one-way hash of the token, never the token itself, plus a short prefix so you can recognise it.

**If you join the waitlist on our website**

- Your email address, when you joined, and which page or link you came from.

**How you use the app** *[Counsel: keep this paragraph only if product events ship; see open question 4.]* We record a small set of events to see whether the app works: a session started, finished, a proof taken, a card shared (and the target app if iOS tells us), a reminder opened. These are tied to your account ID. They are not used for advertising.

## What we do not collect

- Your location. No GPS, no gym check-in, and location data is stripped from photos before upload.
- Your body weight, measurements, calories, heart rate or any Apple Health data.
- Your contacts, your photo library, your browsing history or any advertising identifier.
- Payment information. PGYM v1 has no payments.
- Crash or performance reports from a third-party SDK. v1 includes none.

## Why we use it

| We use | To |
|---|---|
| Email, name, account ID | Sign you in, show your name, contact you about your account |
| Year of birth | Apply the minimum age and keep the physique score off for anyone under 18 |
| Goal, days, reminder time, units, time zone | Show your week, remind you on your gym days, show weights in your units |
| Routines, sessions, sets, exercise stats | Log your training, fill in last session's weights, show progress and bests |
| Photo and card | Make your proof card, show your proof wall, and, only with your consent, produce the physique score |
| Streak, proof count, server timestamp | Count your weeks and make each proof a record of when you showed up |
| Physique score and tip | Show you your score and tip, compared only with your own earlier scores |
| Agent token records | Let an AI agent you choose read your own PGYM data, and let you revoke it |
| Waitlist email | Tell you when PGYM launches |
| Usage events, if collected | Find out whether the core loop works and fix what does not |

We do not sell your data. We do not use your training data or photos for advertising or marketing, and we do not share them with ad or analytics networks. *[Counsel: these are product commitments taken from the PGYM design note and Apple guideline 5.1.3(i); Konrad to confirm them as binding before publishing.]*

*[Counsel: add the legal bases for processing if [JURISDICTION] or the launch regions require them, for example under the GDPR. Launch regions are not decided.]*

## Where it is stored

| What | Where | Region |
|---|---|---|
| Account, sign-in record | Google Firebase Authentication | [REGION, not chosen] |
| Profile, routines, sessions, sets, stats, scores, token records, waitlist | Google Cloud Firestore (part of Firebase) | [REGION, not chosen] |
| Proof photos and cards | Amazon Web Services S3, one private bucket, encrypted at rest, all public access blocked | [REGION, not chosen; nearest the first users] |
| A copy of your sessions and cached images | On your iPhone, in the app's storage | Your phone |

Photos are never public. The app shows them to you through links that expire after 1 hour. An agent with photo access gets card links that expire after 10 minutes.

## Who else handles your data

| Company | What they handle | Why |
|---|---|---|
| Google (Firebase Authentication, Cloud Firestore, Cloud Functions, Secret Manager, App Check) | Account, all records above | Runs the app's sign-in, database and server code |
| Google (Google Sign-In) | Your Google sign-in, if you use it | Signs you in |
| Google (Gemini API) | One proof photo per analysed session, only with your consent | Produces the physique score and tip, see the next section |
| Amazon Web Services (S3) | Photos and cards | Stores them |
| Apple (Sign in with Apple, App Attest) | Your Apple sign-in, if you use it; a check that requests come from the real app | Signs you in; blocks fake clients |
| [HOSTING PROVIDER for the website, Vercel proposed] | Website requests and waitlist sign-ups | Hosts [DOMAIN] |
| An AI agent you choose | Whatever scopes you give its token | You asked for it, see "Your agent" |

*[Counsel: Apple guideline 5.1.1(i) requires confirming that each third party gives the same or equal protection as this policy. That needs the providers' current data processing terms, which have not been reviewed. See open question 1.]*

We may disclose data if the law requires it. *[Counsel: wording and scope for [JURISDICTION].]*

## The physique score and Google's Gemini

The physique score is off until you turn it on. Before the first analysis, the app shows a screen that says what is sent and to whom, and asks you to agree.

- **What is sent:** the photo from that one session, with a fixed instruction asking for a score and a tip. Not your name, email, age, sets or anything else.
- **Who receives it:** Google, through the Gemini API. The photo goes from our server to Google, never straight from your phone.
- **When:** each time you stamp a session while the score is on. Only if you are 18 or older by the year of birth you gave.
- **What comes back:** a score from 0 to 100, one training tip, or a refusal. The model is told to refuse when there is no person, more than one person, only a face, someone who looks under 18, or a photo too dark to read. A refused session still counts; it just has no score.
- **Who sees the result:** you. The score is never on your card and the app never shares it. If you give an agent token photo access, that agent can read your scores and tips too.
- **What Google does with the photo:** *[UNKNOWN. Whether Google keeps Gemini API images, for how long, whether people review them and whether they are used to train models is not confirmed. The sentence "Google does not use your photo to train its models" must not be published until card B2 confirms it in Google's current Gemini API terms. See open question 1.]*
- **Turning it off:** Profile, then Privacy and data. Turning it off stops all future analysis and deletes every stored score and tip. Your photos and proofs stay.

The score is an AI estimate from one photo. It is not a measurement of health, body fat or body composition, and it is not medical advice.

## Your agent

You can create a token in the app that lets your own AI agent (for example Claude or a script you wrote) read your PGYM data. You choose what it can read: profile, sessions, stats, and photos, which is off unless you tick it. Tokens can only read; they cannot log sessions or make proofs. You can revoke a token at any time and it stops working at once.

Once your agent has read your data, what it does with that data is up to you and the agent's provider, not PGYM. *[Counsel: confirm this allocation of responsibility is acceptable in [JURISDICTION].]*

## How long we keep it

| Data | Kept until |
|---|---|
| Account, profile, routines, sessions, stats | You delete them or your account |
| One session's photo, card and sets | You delete that session (or all photos, or your account) |
| Physique scores and tips | You turn the score off, delete the session or delete your account |
| Agent token records, including revoked ones | You delete your account *[Konrad to decide whether revoked records are purged sooner]* |
| Copies on your phone | You delete the app, sign out, or the data is deleted on the server and the app syncs |
| Waitlist email | [UNKNOWN: not decided. Proposed: until launch plus [N] days, or until you unsubscribe] |
| Usage events, if collected | [UNKNOWN: not decided] |
| Photos sent to Gemini, on Google's side | [UNKNOWN: depends on Google's terms, open question 1] |
| Backups | [UNKNOWN: whether Firestore or S3 backups or versioning are switched on, and for how long, is not decided] |

Cards you shared to other apps stay wherever you posted them. We cannot delete those.

## Deleting your data

In the app, Profile, then Privacy and data:

- **Delete one session:** removes its photo, card and sets. The proof number is not used again.
- **Delete all photos:** removes every photo and card. Your sets and proof numbers stay.
- **Turn off the physique score:** deletes every score and tip.
- **Delete account:** removes every photo and card, every session, set and routine, your scores and tips, your agent tokens and your sign-in. If you signed in with Apple, PGYM's access to your Apple ID is revoked too. You may be asked to sign in again first, so nobody else can do this on your phone.

Without the app: use the form at [DOMAIN]/delete-account. *[Konrad and counsel: how the form confirms the request comes from the account owner, and how long it takes, are not decided. See open question 5.]*

## Your choices

- Use PGYM without the physique score. It is off by default and the rest of the app works without it.
- Turn the score off at any time, which deletes stored scores.
- Hide your email with Sign in with Apple.
- Give an agent access, choose its scopes, keep photos out of it, set an expiry, revoke it.
- Turn reminders off in iOS Settings. Reminders are sent by your phone, not by our server.
- Deny camera access. You can still log sets, but a session needs a photo to become a proof.
- Export your data: Profile, then Privacy and data, then Export my data, gives you a file with your profile, routines, sessions and sets. *[Format not decided.]*
- Delete one session, all photos, or your account, as above.

*[Counsel: add the rights the law gives in [JURISDICTION] and the launch regions (for example access, correction, portability, objection, complaint to a regulator) and how to exercise them by email at [EMAIL].]*

## Age

You must be [MINIMUM AGE] or older to use PGYM. The app asks your year of birth when you sign up and will not create an account below that age. The physique score is only for people 18 and over: under 18, it cannot be turned on, and our server checks the age again before any analysis. If we learn that someone under [MINIMUM AGE] has an account, we delete it. *[Counsel: [MINIMUM AGE] is open: 13 with the score locked until 18, or 17+ for the whole app. Rules for children's data in [JURISDICTION] and the launch regions apply to the choice.]*

## Security

Photos are in a private, encrypted bucket and only reachable through short-lived links issued to their owner. The database lets each user read and write only their own records. Agent tokens are stored as hashes. API keys for AWS and Gemini live only on our server, never in the app. No system is perfectly secure; if you find a security problem, follow `SECURITY.md` in the code repository or write to [EMAIL].

## Changes

If we change this policy, we will update the date at the top and, for material changes, tell you in the app before they apply. *[Counsel: notice period for [JURISDICTION].]*

## Contact

[COMPANY], [ADDRESS], [EMAIL].
