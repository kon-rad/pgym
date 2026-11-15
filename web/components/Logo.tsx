// The PGYM mark and lockup, path for path from the final logo files (card D1:
// pgym-mark.svg, pgym-icon-mono.svg, pgym-wordmark.svg). Drawn as paths, no font
// dependency. Plate for the mark, Chalk for the letters (colourway 1, "Primary").
//
// pgym-logo-spec.md, "Minimum size": the master mark (with the inner lip) is for
// a 48 px box and up; below that the one-colour mono cut is used, because the
// lip fills in and the mark goes grey.

/** The master mark: rim, lip and check, in the 800-unit box centred on 0,0. */
export const MARK_PATHS = (
  <>
    <path d="M285.3 -92.7 A300 300 0 1 1 122 -274.1" strokeWidth="72" strokeLinecap="butt" />
    <path d="M216.8 -70.5 A228 228 0 1 1 92.7 -208.3" strokeWidth="22" strokeLinecap="butt" />
    <path d="M-136 12 L-44 104 L245 -252.7" strokeWidth="76" strokeLinecap="round" strokeLinejoin="round" />
  </>
)

/** The one-colour small-size cut: no lip, heavier strokes, wider cut. */
export const MONO_PATHS = (
  <>
    <path d="M291.1 -72.6 A300 300 0 1 1 102.6 -281.9" strokeWidth="88" strokeLinecap="butt" />
    <path d="M-136 12 L-44 104 L245 -252.7" strokeWidth="96" strokeLinecap="round" strokeLinejoin="round" />
  </>
)

/** The four wordmark letters, cap height 200, origin at the top left of the P. */
export const LETTER_PATHS = (
  <>
    <path d="M0 0 H76 A44 44 0 0 1 120 44 V80 A44 44 0 0 1 76 124 H44 V200 H0 Z M44 34 H70 A6 6 0 0 1 76 40 V84 A6 6 0 0 1 70 90 H44 Z" />
    <path
      transform="translate(148 0)"
      d="M44 0 H80 A44 44 0 0 1 124 44 V70 H80 V40 A6 6 0 0 0 74 34 H50 A6 6 0 0 0 44 40 V160 A6 6 0 0 0 50 166 H74 A6 6 0 0 0 80 160 V132 H62 V100 H124 V156 A44 44 0 0 1 80 200 H44 A44 44 0 0 1 0 156 V44 A44 44 0 0 1 44 0 Z"
    />
    <path transform="translate(300 0)" d="M0 0 H46 L64 76 L82 0 H128 L86 116 V200 H42 V116 Z" />
    <path transform="translate(456 0)" d="M0 0 H54 L78 104 L102 0 H156 V200 H114 V80 L94 160 H62 L42 80 V200 H0 Z" />
  </>
)

/** Smallest drawn box, in px, at which the master mark is allowed. */
export const MASTER_MIN_PX = 48

export function Mark({ size = 32, title }: { size?: number; title?: string }) {
  return (
    <svg
      viewBox="-400 -400 800 800"
      width={size}
      height={size}
      role={title ? 'img' : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
    >
      <g transform="rotate(-8)" fill="none" stroke="var(--plate)">
        {size >= MASTER_MIN_PX ? MARK_PATHS : MONO_PATHS}
      </g>
    </svg>
  )
}

// The lockup's mark sits at scale 0.4 in an 800-unit box: 320 units of a
// 290-unit-high viewBox. So the mark's box in px is height * 320 / 290.
export function lockupMarkPx(height: number): number {
  return (height * 320) / 290
}

export function Lockup({ height = 28, label = true }: { height?: number; label?: boolean }) {
  // viewBox trimmed to the drawn area of pgym-wordmark.svg (no ground rect).
  const width = Math.round((height * 1012) / 290)
  const master = lockupMarkPx(height) >= MASTER_MIN_PX
  return (
    <svg
      viewBox="-370 -45 1012 290"
      width={width}
      height={height}
      role={label ? 'img' : undefined}
      aria-label={label ? 'PGYM' : undefined}
      aria-hidden={label ? undefined : true}
      data-cut={master ? 'master' : 'mono'}
    >
      <g transform="translate(-215 100) scale(0.4) rotate(-8)" fill="none" stroke="var(--plate)">
        {master ? MARK_PATHS : MONO_PATHS}
      </g>
      <g fill="var(--chalk)" fillRule="evenodd">
        {LETTER_PATHS}
      </g>
    </svg>
  )
}
