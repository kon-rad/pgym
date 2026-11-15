import { createHash } from 'node:crypto'
import { cert, getApps, initializeApp, type App } from 'firebase-admin/app'
import { FieldValue, getFirestore } from 'firebase-admin/firestore'
import type { WaitlistStore } from './store'

// Writes `waitlist/{id}` with { email, createdAt, source }, as fixed in the architecture note.
// The document id is the SHA-256 of the normalised email, so `create()` stores each
// email once: a second signup hits ALREADY_EXISTS and is reported as 'exists'.

const APP_NAME = 'pgym-web'
const ALREADY_EXISTS = 6 // gRPC status code

export class WaitlistConfigError extends Error {}

function firebaseApp(): App {
  const existing = getApps().find((a) => a.name === APP_NAME)
  if (existing) return existing

  const projectId = process.env.FIREBASE_PROJECT_ID
  if (!projectId) throw new WaitlistConfigError('FIREBASE_PROJECT_ID is not set')

  // Local: the Firestore emulator needs only the project id.
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    return initializeApp({ projectId }, APP_NAME)
  }

  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL
  // Hosts store multi-line keys with literal "\n"; turn them back into newlines.
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n')
  if (!clientEmail || !privateKey) {
    throw new WaitlistConfigError('FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY must be set')
  }
  return initializeApp({ credential: cert({ projectId, clientEmail, privateKey }), projectId }, APP_NAME)
}

export function waitlistDocId(email: string): string {
  return createHash('sha256').update(email).digest('hex')
}

export function createFirestoreWaitlistStore(): WaitlistStore {
  return {
    async add({ email, source }) {
      const db = getFirestore(firebaseApp())
      try {
        await db.collection('waitlist').doc(waitlistDocId(email)).create({
          email,
          source,
          createdAt: FieldValue.serverTimestamp(),
        })
        return 'created'
      } catch (err) {
        if ((err as { code?: unknown }).code === ALREADY_EXISTS) return 'exists'
        throw err
      }
    },
  }
}
