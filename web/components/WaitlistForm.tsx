'use client'

import Link from 'next/link'
import { useEffect, useId, useRef, useState, useSyncExternalStore, type FormEvent } from 'react'
import { joinedStore } from '@/lib/waitlist/joined-store'
import { FORM_NOTE, MESSAGES } from '@/lib/waitlist/messages'
import { normalizeEmail, normalizeSource } from '@/lib/waitlist/validate'
import { Mark } from './Logo'

type Status = 'idle' | 'sending' | 'joined' | 'invalid' | 'limited' | 'unavailable' | 'badRequest'

const OUTCOMES = new Set<Status>(['joined', 'invalid', 'limited', 'unavailable', 'badRequest'])

/** pgym-landing-design.md section 3: no answer in 10 s is the "did not send" error. */
export const SEND_TIMEOUT_MS = 10_000

function WarningGlyph() {
  return (
    <svg className="field-glyph" width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="M8 4.2v4.6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
      <circle cx="8" cy="11.4" r="1.1" fill="currentColor" />
    </svg>
  )
}

/**
 * The waitlist form, in the four states of pgym-landing-design.md section 3:
 * empty, sending, done and error, all inside one fixed box so nothing on the page
 * moves. Works without JavaScript (a plain POST that redirects back to
 * /?waitlist=<outcome>#join); with JavaScript it posts JSON and answers in place.
 * The hero form and the final-call form share the done state.
 */
export function WaitlistForm({
  source,
  readQuery = false,
  inputId,
}: {
  source: string
  readQuery?: boolean
  /** A fixed id for the email field, so the nav button can focus the hero form. */
  inputId?: string
}) {
  const [status, setStatus] = useState<Status>('idle')
  const joined = useSyncExternalStore(joinedStore.subscribe, joinedStore.get, joinedStore.getServer)
  const generatedId = useId()
  const fieldId = inputId ?? `${generatedId}-email`
  const messageId = `${generatedId}-message`
  const inputRef = useRef<HTMLInputElement>(null)
  const sourceRef = useRef<HTMLInputElement>(null)
  const doneRef = useRef<HTMLDivElement>(null)
  const submittedHere = useRef(false)

  // After a no-JavaScript post the server redirects back with the outcome in the query.
  // An utm_source in the address names the channel the sign-up came from.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const utm = params.get('utm_source')
    if (utm && sourceRef.current) sourceRef.current.value = normalizeSource(utm)
    if (!readQuery) return
    const outcome = params.get('waitlist') as Status | null
    if (outcome && OUTCOMES.has(outcome)) {
      if (outcome === 'joined') joinedStore.set(true)
      // eslint-disable-next-line react-hooks/set-state-in-effect -- one read of the URL after hydration
      else setStatus(outcome)
      const url = new URL(window.location.href)
      url.searchParams.delete('waitlist')
      window.history.replaceState(null, '', url.pathname + url.search + url.hash)
    }
  }, [readQuery])

  // Focus moves to the done box, but only in the form that was sent.
  useEffect(() => {
    if (joined && submittedHere.current) doneRef.current?.focus()
  }, [joined])

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (status === 'sending') return
    const data = new FormData(event.currentTarget)
    if (!normalizeEmail(data.get('email'))) {
      setStatus('invalid')
      inputRef.current?.focus()
      return
    }
    setStatus('sending')
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), SEND_TIMEOUT_MS)
    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email: data.get('email'),
          source: data.get('source'),
          company: data.get('company'),
        }),
        signal: controller.signal,
      })
      const body = (await res.json().catch(() => null)) as { status?: Status } | null
      const next = body?.status && OUTCOMES.has(body.status) ? body.status : 'unavailable'
      if (next === 'joined') {
        submittedHere.current = true
        setStatus('idle')
        joinedStore.set(true)
        return
      }
      setStatus(next)
      inputRef.current?.focus()
    } catch {
      setStatus('unavailable')
      inputRef.current?.focus()
    } finally {
      clearTimeout(timer)
    }
  }

  if (joined) {
    return (
      <div className="waitlist">
        <div className="waitlist-done" role="status" tabIndex={-1} ref={doneRef}>
          <Mark size={24} />
          <span>On the list.</span>
        </div>
        <p className="form-message">{MESSAGES.joined}</p>
      </div>
    )
  }

  const error = status !== 'idle' && status !== 'sending' ? MESSAGES[status] : ''
  const sending = status === 'sending'

  return (
    <form className="waitlist" action="/api/waitlist" method="post" onSubmit={onSubmit} noValidate>
      <div className="waitlist-row">
        <label htmlFor={fieldId} className="visually-hidden">
          Your email
        </label>
        <span className={`field${error ? ' field-error' : ''}`}>
          <input
            ref={inputRef}
            id={fieldId}
            className="input"
            type="email"
            name="email"
            required
            maxLength={254}
            autoComplete="email"
            inputMode="email"
            placeholder="you@email.com"
            readOnly={sending}
            aria-invalid={error ? true : undefined}
            aria-describedby={error ? messageId : undefined}
          />
          {error ? <WarningGlyph /> : null}
        </span>
        <input ref={sourceRef} type="hidden" name="source" defaultValue={source} />
        <div className="honeypot" aria-hidden="true">
          <label>
            Company
            <input type="text" name="company" tabIndex={-1} autoComplete="off" />
          </label>
        </div>
        <button
          className={`btn btn-primary${sending ? ' is-sending' : ''}`}
          type="submit"
          aria-busy={sending || undefined}
          aria-disabled={sending || undefined}
        >
          {sending ? 'Sending' : 'Join the waitlist'}
        </button>
      </div>
      <p id={messageId} className="form-message" role={error ? 'alert' : undefined}>
        {error}
      </p>
      <p className="form-note">
        {FORM_NOTE} <Link href="/privacy">Privacy</Link>
      </p>
    </form>
  )
}
