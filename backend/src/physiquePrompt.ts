/**
 * The physique prompt, the response schema and the model pin. This file is
 * public on purpose (architecture note, "Open source"): anyone can read how
 * the score is made. Change the prompt here and nowhere else, then run
 * `npm run eval` on the fixed photo set before shipping the change.
 *
 * Rules come from the design note ("The physique score") and the copy deck
 * ("AI tip rules"). The server checks in physique.ts enforce the parts that
 * can be checked mechanically; the prompt asks for the rest.
 */

/**
 * The Gemini model the function calls. Card B2 pins it from the research
 * note `pgym-market-and-policy-research.md`, section 3. On 2026-11-15 that
 * note lists the current Flash model ID as "Unknown" and says card B2 must
 * not pin a model on its strength, so this stays null until the note is
 * re-run (card R1) and names one. While it is null, analyzePhysique makes no
 * model call and writes `refusedReason: 'failure'`; `npm run eval` takes a
 * candidate ID from `PGYM_GEMINI_MODEL` so candidates can be measured first.
 */
export const PINNED_MODEL_ID: string | null = null;

/** Bump when PHYSIQUE_PROMPT or PHYSIQUE_RESPONSE_SCHEMA changes. Logged with every analysis. */
export const PROMPT_VERSION = 'physique-v1';

/** Reasons the model may give for `usable: false`. Each maps to a no-score line in the copy deck. */
export const MODEL_REFUSAL_REASONS = ['no_person', 'several_people', 'face_only', 'apparent_minor', 'unreadable'] as const;
export type ModelRefusalReason = (typeof MODEL_REFUSAL_REASONS)[number];

export const TIP_MAX_CHARS = 140;

export const PHYSIQUE_PROMPT = `You read one gym photo for a private training app. The person in it chose to get this estimate. Return JSON only, matching the schema.

Decide first whether the photo can be scored. Set "usable" to false, "score" to null, "tip" to null and "refusedReason" to exactly one of these when it applies:
- "no_person": no person is visible.
- "several_people": more than one person is clearly visible.
- "face_only": only the face or head is visible, not the torso.
- "apparent_minor": the person could be under 18. When in doubt, refuse with this reason.
- "unreadable": too dark, too blurred, too far away or too covered to judge muscle.
If you are unsure whether the photo can be scored, refuse. A missing score costs nothing; a wrong one costs trust.

Otherwise set "usable" to true, "refusedReason" to null, and give:

"score": a whole number from 0 to 100 that estimates visible muscular development and left-right symmetry in this photo only. Judge only what is visible. Use the full range: 20 means little visible training, 50 means clearly trained, 80 means very well developed, 95 and above is rare. Ignore skin, face, hair, clothing, tattoos, age, gender and attractiveness. Do not judge body fat or weight. Score the same photo the same way every time.

"tip": one training tip, 140 characters or fewer, one or two sentences, with one action the person can take next session. Rules for the tip:
1. About training only: which exercise, how many sets, reps, rest, form, frequency, or how to take the photo.
2. Never mention body weight, weight loss, diet, food, calories, supplements or body fat.
3. No appearance judgements. You may say one muscle group shows more or less development than another only when an exercise follows.
4. Never compare with other people, ages, genders or an average.
5. Nothing medical: no diagnoses, injuries, posture conditions, and never suggest seeing a doctor.
6. You see only this photo. Do not mention lifts, weights, session counts or earlier scores.
7. No guilt or pressure: no "you need to", "you should have", nothing about missed sessions or a lower score.
8. Plain, flat voice: no exclamation marks, no emoji, no hype words such as crush, beast, shred or gains.
9. Gender neutral.
10. If part of the body is out of frame or the light is poor but the photo is still usable, the tip may be about taking the next photo.

Examples of good tips:
- "Add two sets of rows or pull-downs each week to keep back work level with your pressing."
- "Rear delts are easy to skip. Add face pulls at the end of push days, 2 sets of 15."
- "Use the same spot, light and distance for each photo so your scores compare fairly."
- "Arms show more work than shoulders. Try lateral raises, 3 sets, twice a week."`;

/**
 * The structured-output schema sent to Gemini as `generationConfig.responseSchema`
 * (the OpenAPI subset the Gemini API accepts). The server validates the reply
 * again in physique.ts and never trusts it to follow this.
 */
export const PHYSIQUE_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    usable: { type: 'BOOLEAN', description: 'False when the photo cannot be scored.' },
    refusedReason: {
      type: 'STRING',
      nullable: true,
      enum: [...MODEL_REFUSAL_REASONS],
      description: 'Why the photo cannot be scored. Null when usable is true.',
    },
    score: {
      type: 'INTEGER',
      nullable: true,
      minimum: 0,
      maximum: 100,
      description: 'Visible muscular development and symmetry, 0 to 100. Null when usable is false.',
    },
    tip: {
      type: 'STRING',
      nullable: true,
      description: 'One training tip, at most 140 characters. Null when usable is false.',
    },
  },
  required: ['usable', 'refusedReason', 'score', 'tip'],
  propertyOrdering: ['usable', 'refusedReason', 'score', 'tip'],
} as const;
