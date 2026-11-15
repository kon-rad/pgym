// The PGYM mark and lockup, from the final logo files (card D1). Drawn as paths,
// no font dependency. Plate on Ink for the mark, Chalk for the letters.

const MARK_PATHS = (
  <>
    <path d="M285.3 -92.7 A300 300 0 1 1 122 -274.1" strokeWidth="72" strokeLinecap="butt" />
    <path d="M216.8 -70.5 A228 228 0 1 1 92.7 -208.3" strokeWidth="22" strokeLinecap="butt" />
    <path d="M-136 12 L-44 104 L245 -252.7" strokeWidth="76" strokeLinecap="round" strokeLinejoin="round" />
  </>
)

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
        {MARK_PATHS}
      </g>
    </svg>
  )
}

export function Lockup({ height = 28, label = true }: { height?: number; label?: boolean }) {
  // viewBox trimmed to the drawn area of pgym-wordmark.svg (no ground rect).
  const width = Math.round((height * 1012) / 290)
  return (
    <svg
      viewBox="-370 -45 1012 290"
      width={width}
      height={height}
      role={label ? 'img' : undefined}
      aria-label={label ? 'PGYM' : undefined}
      aria-hidden={label ? undefined : true}
    >
      <g transform="translate(-215 100) scale(0.4) rotate(-8)" fill="none" stroke="var(--plate)">
        {MARK_PATHS}
      </g>
      <g fill="var(--chalk)" fillRule="evenodd">
        <path d="M0 0 H76 A44 44 0 0 1 120 44 V80 A44 44 0 0 1 76 124 H44 V200 H0 Z M44 34 H70 A6 6 0 0 1 76 40 V84 A6 6 0 0 1 70 90 H44 Z" />
        <path
          transform="translate(148 0)"
          d="M44 0 H80 A44 44 0 0 1 124 44 V70 H80 V40 A6 6 0 0 0 74 34 H50 A6 6 0 0 0 44 40 V160 A6 6 0 0 0 50 166 H74 A6 6 0 0 0 80 160 V132 H62 V100 H124 V156 A44 44 0 0 1 80 200 H44 A44 44 0 0 1 0 156 V44 A44 44 0 0 1 44 0 Z"
        />
        <path transform="translate(300 0)" d="M0 0 H46 L64 76 L82 0 H128 L86 116 V200 H42 V116 Z" />
        <path transform="translate(456 0)" d="M0 0 H54 L78 104 L102 0 H156 V200 H114 V80 L94 160 H62 L42 80 V200 H0 Z" />
      </g>
    </svg>
  )
}
