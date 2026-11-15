// What the waitlist route answers, shared by the route and the form.
// Plain and positive. Shown in Chalk on Iron, never in Plate and never in red.

export const MESSAGES = {
  joined: 'You are on the list. We email you once, when PGYM is in the App Store.',
  invalid: 'That email does not look right. Check it and try again.',
  limited: 'Too many tries from here. Wait a minute and try again.',
  unavailable: 'The list is not taking signups right now. Try again later.',
  badRequest: 'Send an email address.',
} as const

export type Outcome = keyof typeof MESSAGES
