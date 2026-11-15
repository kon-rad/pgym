// What the waitlist route answers, shared by the route and the form. Lines from
// pgym-landing-copy.md, "Waitlist form states". Plain and positive. Shown in Chalk,
// never in Plate and never in red.
//
// The copy's "That email is already on the list." is not used: an address that is
// already stored gets the same answer as a new one, so the page never says who is
// on the list (pgym-landing-design.md section 3, "Done").

export const MESSAGES = {
  joined: 'You are on the list. Check your inbox.',
  invalid: 'That does not look like an email address.',
  // No line in the copy for the rate limit; written in the same voice.
  limited: 'Too many tries from here. Try again in a minute.',
  unavailable: 'Something went wrong on our side. Try again in a minute.',
  badRequest: 'That does not look like an email address.',
} as const

export type Outcome = keyof typeof MESSAGES

/** Under the form before launch (pgym-landing-copy.md, "Waitlist form"). */
export const FORM_NOTE = 'We email you twice: when you can test it, and when it is on the App Store. Nothing else.'
