// The waitlist store interface. One real implementation (Firestore, firestore-store.ts)
// and one in-memory implementation for tests.

export interface WaitlistEntry {
  email: string
  source: string
}

export type AddResult = 'created' | 'exists'

export interface WaitlistStore {
  /** Stores the entry once per email. A second call with the same email returns 'exists'. */
  add(entry: WaitlistEntry): Promise<AddResult>
}

export interface MemoryWaitlistStore extends WaitlistStore {
  readonly entries: ReadonlyMap<string, WaitlistEntry & { createdAt: Date }>
}

export function createMemoryWaitlistStore(): MemoryWaitlistStore {
  const entries = new Map<string, WaitlistEntry & { createdAt: Date }>()
  return {
    entries,
    async add(entry) {
      if (entries.has(entry.email)) return 'exists'
      entries.set(entry.email, { ...entry, createdAt: new Date() })
      return 'created'
    },
  }
}
