---
title: "Why proof of gym"
slug: why-proof-of-gym
description: "Why PGYM exists, how the proof card works, why the streak counts weeks, why the score is private, and why the code is open."
author: "PGYM"
date: "[PUBLISH-DATE]"
---


# Why proof of gym

Most of training is showing up. The hard part is rarely the last set of squats. It is the evening when the gym is across town and the sofa is right here.

PGYM is an iPhone app built for that evening. You log your sets, take one photo at the end, and get a card with the date, the time, what you did and a number. Proof #001 is the first time. Proof #042 is the forty-second. That is the whole loop.

## Why another gym app

Plenty of apps track lifts. They are good spreadsheets. They are not built to get you through the door.

PGYM is built around the moment after the last set. Training pays off in months. A card pays off now. You stamp it, you see the week move, and you send it to a friend or keep it on your proof wall.

Think of it as Strava for the gym, with the photo as the receipt.

## How the proof card works

A card is only worth something if it is hard to fake, so a few rules are built in.

The photo comes from the camera inside the app. There is no button to import from your library, because a library photo could be from any day.

The time on the card comes from the server, not your phone. When the photo arrives, the server sets the timestamp and gives the session its proof number. A phone clock can be changed.

A session counts when it has at least one logged set and one photo. Without the set it is a selfie app. Without the photo it is a tracker.

One session, one proof. Retaking the photo replaces it and never adds a second number. Your proof numbers count up and are never reused, so #042 always means the forty-second time you showed up.

No GPS check-in, no anti-cheat. The first person you are proving it to is yourself.

The ordinary card shows the photo, a stamp with the proof number and your streak, the timestamp, the session name, and three numbers: sets, weight lifted, time. Pro members who request AI analysis can also choose score overlays when they share again. The ordinary card stays free of scores.

## Why the streak counts weeks

Rest days are part of training. A daily streak that breaks on a rest day punishes you for doing it right.

So PGYM asks one question when you start: how many days a week? Two to six. You pick the days and the time. Hit the number and the week locks. Rest days never touch it.

There is slack built in. Every four weeks you hit earns a pass week, used on its own when a week falls short, so one bad week with a cold or a trip doesn't erase months. When a week is missed anyway, Monday opens with "New week. 0 of 4." and no mention of what happened. A fresh start does more than a guilt trip.

You will never get a notification saying you broke something. You get one reminder on a gym day, and none once the session is logged.

## Why the score is private

PGYM Pro offers optional AI analysis: six visual dimension scores, one overall 0 to 100 score, three coaching sentences and one encouraging sentence from a stamped session photo.

An AI judging a body is the feature most able to hurt someone, so it comes with rules.

- It is off until you turn it on, on its own screen, after you have read what is sent and who sees it.
- Results stay in your private workout history unless you explicitly choose a score-sharing card layout.
- Use it to compare your own photos over time, not to rank yourself against strangers.
- An unsuitable or poorly framed photo may not be scored. The session still counts.
- Under 18, it can't be turned on.
- Coaching is about training and photo consistency, not weight loss, diet or body fat.
- Turn it off and your stored scores are deleted.

Every score is an AI estimate from one photo, not medical advice. Light and pose move the number. Treat it as one more signal, not a verdict. The full capture and chart guide is in [Measure the work. See the change.](/blog/measure-the-work-see-the-change).

## Open source, and built for your agent

The code is public at [github.com/kon-rad/pgym](https://github.com/kon-rad/pgym). The streak logic, the security rules and the prompt behind the physique score are all in the repo. If you want to know how your score is made, you can read it. If you find a security hole, there is a private way to report it on the [open source](/open-source) page.

PGYM is also built for the AI agents people now use. In the app you can create a token for your own agent and choose what it can read: your profile, your sessions, your stats, and your photos only if you tick that box. It can't change anything. Your agent can tell you whether you hit your week, sum up your month, or plan your next push day from your lift history. It can't create a proof. Only you can, in the gym, with the camera.

Point your agent at [/skill.md](/skill.md). The details for people are on [For your agent](/agents).

## What it is not

No feed, no leaderboard, no comparing you with strangers. Sharing goes out to the apps you already use. The focus stays on one question: did you show up this week?

The [guide](/guide) walks through every screen. Proof #001 is waiting.
