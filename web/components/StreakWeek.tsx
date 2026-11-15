import { WEEK_DAYS, WEEK_DONE } from './AppScreens'
import { Stamp } from './ProofCard'

// The streak section's visual (pgym-landing-design.md 2.5): no screenshot, the
// week row rebuilt from the app's components. Seven day rings (36 px on a phone,
// 56 px from 768 px), four done in Plate with an Ink check, three empty with a
// 2 px Ash ring, mono day letters under them, "4 OF 4", then the streak stamp
// "7 WEEKS RUNNING" at -4 degrees. Screen readers hear one sentence.

export const WEEK_GOAL = 4

export function StreakWeek({ weeks = 7 }: { weeks?: number }) {
  const done = WEEK_DONE.filter(Boolean).length
  return (
    <div
      className="streak-visual"
      role="img"
      aria-label={`Example week: ${done} of ${WEEK_GOAL} sessions this week, ${weeks} weeks running.`}
      data-reveal
    >
      <div className="week-row" aria-hidden="true">
        {WEEK_DAYS.map((d, i) => (
          <span className="day" key={i}>
            <span className={`day-ring${WEEK_DONE[i] ? ' done' : ''}`}>
              {WEEK_DONE[i] ? (
                <svg viewBox="0 0 14 14">
                  <path
                    d="M2.5 7.5 5.5 10.5 11.5 3.5"
                    fill="none"
                    stroke="#0B0B0C"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              ) : null}
            </span>
            <span className="day-letter">{d}</span>
          </span>
        ))}
      </div>
      <p className="week-count" aria-hidden="true">
        {done} OF {WEEK_GOAL}
      </p>
      <div className="streak-stamp" aria-hidden="true">
        <Stamp top="STREAK" big={`${weeks} WEEKS`} bottom="RUNNING" />
      </div>
    </div>
  )
}
