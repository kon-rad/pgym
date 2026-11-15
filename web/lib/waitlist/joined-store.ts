// The hero form and the final-call form share one "joined" state: after one of
// them succeeds, both show the done box (pgym-landing-design.md 2.9). A tiny
// external store, read with useSyncExternalStore. Server render is never joined.

type Listener = () => void

let joined = false
const listeners = new Set<Listener>()

export const joinedStore = {
  get: (): boolean => joined,
  getServer: (): boolean => false,
  set(value: boolean) {
    if (joined === value) return
    joined = value
    listeners.forEach((l) => l())
  },
  subscribe(listener: Listener): () => void {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
}
