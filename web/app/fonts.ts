import localFont from 'next/font/local'

// The three faces, self-hosted from files in app/fonts (SIL Open Font Licence, see OFL-*.txt).
// No request goes to a font CDN.

export const anton = localFont({
  src: [{ path: './fonts/anton-latin-400-normal.woff2', weight: '400', style: 'normal' }],
  variable: '--font-anton',
  display: 'swap',
  fallback: ['Impact', 'Haettenschweiler', 'Arial Narrow', 'sans-serif'],
})

export const archivo = localFont({
  src: [
    { path: './fonts/archivo-latin-400-normal.woff2', weight: '400', style: 'normal' },
    { path: './fonts/archivo-latin-500-normal.woff2', weight: '500', style: 'normal' },
    { path: './fonts/archivo-latin-600-normal.woff2', weight: '600', style: 'normal' },
    { path: './fonts/archivo-latin-700-normal.woff2', weight: '700', style: 'normal' },
  ],
  variable: '--font-archivo',
  display: 'swap',
  fallback: ['system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'sans-serif'],
})

export const jetbrainsMono = localFont({
  src: [
    { path: './fonts/jetbrains-mono-latin-400-normal.woff2', weight: '400', style: 'normal' },
    { path: './fonts/jetbrains-mono-latin-700-normal.woff2', weight: '700', style: 'normal' },
  ],
  variable: '--font-mono',
  display: 'swap',
  preload: false,
  fallback: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
})
