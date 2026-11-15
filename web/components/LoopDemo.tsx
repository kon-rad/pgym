import { CameraScreen, CompleteScreen, Phone, SessionScreen } from './AppScreens'
import type { ProofCardProps } from './ProofCard'

// "The loop" (pgym-landing-design.md 2.3), with the home page's log, photo, card
// sequence played across its three frames. Each step is a frame (frameS at
// 390 px, frameM from 768 px), then its number, its line and one sentence;
// stacked on a phone, three columns on desktop.
//
// The sequence is CSS only, one 9 s timeline shared by every animated part (see
// "Loop sequence" in globals.css): 0 to 3 s the sets check off, 3 to 5.5 s the
// shutter fires, 5.5 to 9 s the card is stamped. The step being played gets a
// Plate frame edge. It waits until it scrolls into view, and with Reduce Motion
// it is a still: every set checked, the card stamped.

/** Copy: pgym-landing-copy.md, section 3, word for word. */
export const LOOP_STEPS = [
  {
    title: 'Log your sets.',
    body: "Tap the check on each set. Last session's weights are already filled in, so a normal set is one tap.",
    label: 'An animation of the loop, step 1 of 3: the active session: three sets checked off, the fourth to go, the rest timer running.',
  },
  {
    title: 'Take one photo.',
    body: 'At the end, tap Finish and take proof. The photo comes from the PGYM camera, never from your camera roll.',
    label: 'An animation of the loop, step 2 of 3: the PGYM camera pointed at a barbell, with the shutter button.',
  },
  {
    title: 'Get your proof.',
    body: 'Pick a filter and tap Stamp it. Our server adds the time and your proof number. Share it wherever you already post.',
    label: 'An animation of the loop, step 3 of 3: the session complete screen: the card stamped proof #043, week 7 locked, a new best on bench press.',
  },
] as const

export function LoopDemo({ card }: { card: ProofCardProps }) {
  const screens = [<SessionScreen key="log" />, <CameraScreen key="photo" />, <CompleteScreen key="card" card={card} />]
  return (
    <ol className="loop" data-reveal>
      {LOOP_STEPS.map((step, i) => (
        <li className={`loop-step ld-step-${i + 1}`} key={step.title}>
          <Phone size="s" desktop="m" label={step.label} className="loop-phone">
            {screens[i]}
          </Phone>
          <span className="label loop-n">{String(i + 1).padStart(2, '0')}</span>
          <h3 className="loop-title">{step.title}</h3>
          <p>{step.body}</p>
        </li>
      ))}
    </ol>
  )
}
