---
title: "Terms of use"
description: "Age, acceptable use, no medical advice, the AI estimate, who owns the photos, the agent API and ending your account."
path: /terms
updated: 2026-11-15
---

<!-- Copied from the vault's copy/pgym-terms-draft.md, Part 1 (the terms text), on 2026-11-15. Headings moved up one level and wikilinks written out. Section 5's licence note now names MIT: the repo's LICENSE is MIT, confirmed by Konrad on 2026-11-15. Bracketed italic notes are for counsel and come out before publishing. -->

# PGYM terms of use

Your gym photos stay on your phone. If an eligible adult enables optional AI analysis, one reduced JPEG is sent through PGYM to an open-source vision model hosted by Together AI for transient analysis. PGYM does not persist the JPEG. The optional workout insight stays on your device. PGYM Pro can store seven visual physique scores and coaching in your private session. You choose whether to share scores on a card. These are AI estimates, not medical conclusions.

Effective [EFFECTIVE DATE]. These terms are an agreement between you and [COMPANY], [ADDRESS] ("we"). By creating an account you agree to them and to the Privacy Policy at [DOMAIN]/privacy. If you do not agree, do not use PGYM.

## 1. What PGYM is

PGYM is an iPhone app for logging gym sessions. You log sets, take one photo in the app and get a card with the date, the time, your session stats and a proof number. Eligible adults with PGYM Pro can request six visual dimension scores, an overall score, coaching and encouragement. You can give your own AI agent read access to structured workout data. Core workout logging and ordinary proof cards remain free; Pro requires an active subscription. Localized price and trial terms appear in the app before purchase.

## 2. Age

You must be [MINIMUM AGE] or older to create an account. The physique score is only for people 18 and over. You must give your real year of birth. If you are under the age of majority where you live, you confirm that a parent or guardian agrees to these terms. *[Counsel: whether this sentence is needed depends on [MINIMUM AGE] and [JURISDICTION].]* We may delete an account we believe belongs to someone under [MINIMUM AGE].

## 3. Your account

- Keep your sign-in secure. You are responsible for what happens under your account and your agent tokens.
- One person per account. Do not create an account for someone else or share it.
- Tell us at [EMAIL] if you think someone else has used your account.

## 4. Your photos and data are yours

You own the photos you take in PGYM, the cards made from them and the data you enter. We do not claim ownership of any of it.

To run PGYM, you give us a permission that is limited to the following, and to nothing else:

- store your photos, cards and data;
- make your card from your photo and your session;
- show them to you, and to an agent you give a token to, within the scopes you choose;
- if you turned on photo insight, transiently send one reduced JPEG to Together AI to produce one short workout suggestion;
- keep backups and copies needed to run the service securely. *[Counsel: whether backups exist is open, see the privacy policy draft.]*

The permission is worldwide and free of charge, it does not let us sell your content or use it in advertising, and it ends when you delete the content or your account, except for cards you already shared outside PGYM. We will not use your photo in our marketing unless you give separate, specific permission. *[Counsel: wording of the licence for [JURISDICTION].]*

When you share a card to another app, that app's terms apply to the copy you posted. We cannot remove it from there.

## 5. Acceptable use

When you use PGYM you agree to:

- take photos of yourself only. Do not photograph other people without their permission, and never photograph anyone who is or looks under 18;
- keep photos decent: no nudity or sexual content;
- not upload anything illegal, or anything that infringes someone else's rights;
- not try to fake a proof: do not tamper with the app, its timestamps or the server to produce a proof you did not take;
- not attack, overload or probe PGYM's servers, except under the security policy in the code repository (`SECURITY.md`);
- use the agent API only for your own account, within its rate limit (60 requests a minute per token), and not to collect other people's data;
- not use PGYM, its cards or its scores to harass, shame or rank other people.

PGYM is open source. Reading, copying and changing the code is governed by its licence, not by this section. The licence is MIT. Running your own copy of the code is not the PGYM service, and these terms do not cover it.

## 6. No medical advice

PGYM is not a medical device and does not give medical, health, diet or nutrition advice. Nothing in the app, including the physique score, the tips, the estimated one-rep max or the streak, tells you whether you are healthy or what you should eat or weigh.

Exercise carries risk of injury. Check with a doctor before you start a training programme, if you have a health condition, or if you are unsure whether an exercise is safe for you. Stop if something hurts. You train at your own risk. *[Counsel: assumption-of-risk wording for [JURISDICTION].]*

If you are struggling with how you see your body or with eating, talk to a doctor or a qualified professional. You can turn the physique score off at any time, which also deletes every stored score.

## 7. The physique score is an AI estimate

If you turn it on:

- Optional Pro physique analysis scores six visible dimensions and one overall estimate from a photo. It cannot measure body composition, metabolic health or injury risk.
- Light, clothing, pose, distance and camera change scores. Two photos taken minutes apart can score differently. The history graph includes a seven-day rolling average, but that does not remove measurement uncertainty.
- The model may refuse a photo, for example when there is no person, more than one person, only a face, someone who looks under 18, or poor light. A refused session still counts as a proof.
- The tip is about training only. It is generated by AI and may not suit you. Use your judgement.
- Scores are private in your session until you explicitly select a score-sharing card layout. The normal workout card does not include them. The agent API has no score or photo scope.
- The prompt that produces the score is public in the code repository, so you can read how it works.

Scores are AI estimates from a photo, not medical advice.

## 8. What a proof number means

A proof number counts the times you completed a session with a photo in PGYM. The timestamp is the time our server received the photo. A proof does not confirm where the photo was taken, who is in it, that the logged sets happened, or anything else. Do not present a PGYM card as verification to a third party, and do not rely on someone else's card as verification. *[Counsel: wording for [JURISDICTION].]*

## 9. Your agent and the API

You can create tokens that let an AI agent read your PGYM data. Treat a token like a password. Anyone who has it can read what its scopes allow until it expires or you revoke it. What your agent, and the company that runs it, does with your data is between you and them. Tokens cannot create sessions or proofs. We may change, limit or stop the API, and we may revoke a token that breaks section 5. The API is versioned (`/v1`); we will try to give notice before removing a version. *[Notice period not decided.]*

## 10. Changes to PGYM and to these terms

PGYM is new and will change. We may add, change or remove features. If we change these terms in a way that matters, we will tell you in the app before the change applies. If you keep using PGYM after that, the new terms apply. If you do not agree, delete your account. *[Counsel: notice period and consent mechanism for [JURISDICTION].]*

## 11. Ending your account

- **You** can delete your account at any time in the app (Profile, then Privacy and data, then Delete account) or with the form at [DOMAIN]/delete-account. Deletion removes your photos, cards, sessions, scores, tokens and sign-in, as described in the Privacy Policy. It cannot be undone.
- **We** may suspend or close your account if you break these terms, if the law requires it, or if your use puts other people or the service at risk. Where we can, we will tell you why and give you a chance to export your data first. *[Counsel: notice and appeal wording.]*
- **If we shut PGYM down,** we will tell you in the app at least [N] days before and let you export your data. *[N not decided.]*

Sections 4 (for content you already shared), 6, 7, 8 and 12 to 14 continue after your account ends.

## 12. Warranty and liability

*[Counsel to draft for [JURISDICTION]: the service provided as is, the limits of liability, and the consumer rights that cannot be excluded. No text is proposed here.]*

## 13. Governing law and disputes

*[Counsel to draft: governing law of [JURISDICTION], courts or dispute process, and any consumer protections in the launch regions.]*

## 14. Apple

These terms are between you and [COMPANY], not Apple. *[Counsel: Apple's Licensed Application End User License Agreement applies to App Store apps unless the developer provides its own; decide whether these terms replace it and add any terms Apple requires. Not checked in this run.]*

## 15. Contact

[COMPANY], [ADDRESS], [EMAIL].
