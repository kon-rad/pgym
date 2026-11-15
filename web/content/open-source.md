---
title: "Open source"
description: "PGYM's code is public. Read it, run it locally, contribute, and report security problems privately."
path: /open-source
---



> **Note:** the licence is shown as MIT. MIT is proposed and not yet confirmed. Remove this line once it is.

# Open source

PGYM is open source. The iPhone app, the server code and this website are in one public repository:

https://github.com/kon-rad/pgym

## Why it's open

PGYM handles photos of people's bodies and an AI score of them. You should be able to check how that works, not take our word for it. In the repo you can read:

- **The physique prompt and its rules**, so you can see exactly how the score is made and when it refuses a photo.
- **The security rules**, which decide that only you can read your data.
- **The streak logic**, so you know how a week gets locked and when a pass week is spent.

Secrets never go in the repo: no API keys, no service-account files, no signing details.

## Licence

MIT. You can use, copy, change and share the code, including commercially, as long as the licence notice stays with it. The full text is in [LICENSE](https://github.com/kon-rad/pgym/blob/main/LICENSE).

## Run it locally

The whole stack runs on a laptop with no cloud account: the Firebase emulator for sign-in, database and server code, MinIO in place of S3 for photos, and a fake AI client in place of Gemini. The steps are in the [README](https://github.com/kon-rad/pgym#run-it-locally).

## Contribute

Bug reports, fixes and ideas are welcome. Open an issue before a large change so we can agree on it first. How to set up, test and send a pull request: [CONTRIBUTING.md](https://github.com/kon-rad/pgym/blob/main/CONTRIBUTING.md).

Everyone taking part follows the [code of conduct](https://github.com/kon-rad/pgym/blob/main/CODE_OF_CONDUCT.md).

## Report a security problem

Please don't open a public issue for a security hole. Report it privately:

- On GitHub: https://github.com/kon-rad/pgym/security/advisories/new
- By email: [EMAIL]

What counts and what happens next: [SECURITY.md](https://github.com/kon-rad/pgym/blob/main/SECURITY.md).

## Built for agents too

Your own AI agent can read your PGYM data with a token you control. See [For your agent](/agents) and the [skill file](/skill.md).

