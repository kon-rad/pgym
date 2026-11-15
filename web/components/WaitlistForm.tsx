'use client'

import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { MESSAGES } from '@/lib/waitlist/messages'
import { Stamp } from './ProofCard'

type Status = 'idle' | 'sending' | 'joined' | 'invalid' | 'limited' | 'unavailable' | 'badRequest'

const OUTCOMES = new Set<Status>(['joined', 'invalid', 'limited', 'unavailable', 'badRequest'])

/**
 * The waitlist form. Works without JavaScript (a plain POST that redirects back to
 * /?waitlist=<outcome>#join); with JavaScript it posts JSON and answers in place.
 */
export function WaitlistForm({ source, readQuery = false }: { source: string; readQuery?: boolean }) {
  const [status, setStatus] = useState<Status>('idle')
  const inputId = useId()
  const errorId = useId()
  const inputRef = useRef<HTMLInputElement>(null)

  // After a no-JavaScript post the server redirects back with the outcome in the query.
  useEffect(() => {
    if (!readQuery) return
    const outcome = new URLSearchParams(window.location.search).get('waitlist') as Status | null
    if (outcome && OUTCOMES.has(outcome)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- one read of the URL after hydration
      setStatus(outcome)
      const url = new URL(window.location.href)
      url.searchParams.delete('waitlist')
      window.history.replaceState(null, '', url.pathname + url.search + url.hash)
    }
  }, [readQuery])

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (status === 'sending') return
    const data = new FormData(event.currentTarget)
    setStatus('sending')
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email: data.get('email'),
          source: data.get('source'),
          company: data.get('company'),
        }),
      })
      const body = (await res.json().catch(() => null)) as { status?: Status } | null
      const next = body?.status && OUTCOMES.has(body.status) ? body.status : 'unavailable'
      setStatus(next)
      if (next !== 'joined') inputRef.current?.focus()
    } catch {
      setStatus('unavailable')
    }
  }

  if (status === 'joined') {
    return (
      <div className="joined" role="status">
        <Stamp top="WAITLIST" big="IN" bottom="SEE YOU AT LAUNCH" />
        <p>{MESSAGES.joined}</p>
      </div>
    )
  }

  const error = status !== 'idle' && status !== 'sending' ? MESSAGES[status] : null

  return (
    <form className="waitlist" action="/api/waitlist" method="post" onSubmit={onSubmit} noValidate={false}>
      <label htmlFor={inputId} className="field-label label">
        Get one email when it is out
      </label>
      <div className="waitlist-row">
        <input
          ref={inputRef}
          id={inputId}
          className="input"
          type="email"
          name="email"
          required
          maxLength={254}
          autoComplete="email"
          inputMode="email"
          placeholder="you@example.com"
          aria-invalid={status === 'invalid' ? true : undefined}
          aria-describedby={error ? errorId : undefined}
        />
        <input type="hidden" name="source" value={source} />
        <div className="honeypot" aria-hidden="true">
          <label>
            Company
            <input type="text" name="company" tabIndex={-1} autoComplete="off" />
          </label>
        </div>
        <button className="btn btn-primary" type="submit" disabled={status === 'sending'}>
          {status === 'sending' ? 'Joining' : 'Join the waitlist'}
        </button>
      </div>
      {error ? (
        <p id={errorId} className="form-error" role="alert">
          {error}
        </p>
      ) : (
        <p className="form-note">One email at launch. Nothing else, and no sharing.</p>
      )}
    </form>
  )
}
