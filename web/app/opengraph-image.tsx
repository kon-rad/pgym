import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { ImageResponse } from 'next/og'

// The Open Graph image, rendered once at build time from the self-hosted fonts.
// Satori reads WOFF but not WOFF2, which is why the two .woff files are kept.

export const alt = 'PGYM. Proof of gym. A proof card stamp: PROOF #042, WEEK 7.'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

const INK = '#0B0B0C'
const IRON = '#17171A'
const CHALK = '#F2EFE8'
const BONE = '#C9C7C1'
const PLATE = '#FF4D1F'

export default async function OpengraphImage() {
  const fonts = join(process.cwd(), 'app', 'fonts')
  const [anton, mono] = await Promise.all([
    readFile(join(fonts, 'anton-latin-400-normal.woff')),
    readFile(join(fonts, 'jetbrains-mono-latin-700-normal.woff')),
  ])

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          background: INK,
          padding: '72px 80px',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', maxWidth: 680 }}>
          <div style={{ fontFamily: 'Mono', fontSize: 24, letterSpacing: 4, color: PLATE }}>PGYM · AN IPHONE APP</div>
          <div
            style={{
              display: 'flex',
              fontFamily: 'Anton',
              fontSize: 148,
              lineHeight: 0.95,
              color: CHALK,
              marginTop: 24,
              textTransform: 'uppercase',
              flexWrap: 'wrap',
            }}
          >
            <span>Proof of gym</span>
            <span style={{ color: PLATE }}>.</span>
          </div>
          <div style={{ fontFamily: 'Mono', fontSize: 26, color: BONE, marginTop: 32, lineHeight: 1.4 }}>
            LOG YOUR SETS. TAKE ONE PHOTO. GET YOUR PROOF.
          </div>
        </div>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            padding: '18px 40px',
            border: `8px solid ${PLATE}`,
            borderRadius: 14,
            background: IRON,
            color: PLATE,
            transform: 'rotate(4deg)',
          }}
        >
          <div style={{ fontFamily: 'Mono', fontSize: 30, letterSpacing: 6 }}>PROOF</div>
          <div style={{ fontFamily: 'Anton', fontSize: 120, lineHeight: 1.05 }}>#042</div>
          <div style={{ fontFamily: 'Mono', fontSize: 26, letterSpacing: 4 }}>WEEK 7</div>
        </div>
      </div>
    ),
    {
      ...size,
      fonts: [
        { name: 'Anton', data: anton, weight: 400, style: 'normal' },
        { name: 'Mono', data: mono, weight: 700, style: 'normal' },
      ],
    },
  )
}
