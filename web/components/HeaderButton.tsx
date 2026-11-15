'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import type { MouseEvent, ReactNode } from 'react'

/**
 * The outlined nav button. On the home page it scrolls to the hero action and,
 * when given a field id, focuses that field; elsewhere it is a plain link to /#join.
 */
export function HeaderButton({ href, focusId, children }: { href: string; focusId?: string; children: ReactNode }) {
  const pathname = usePathname()

  function onClick(event: MouseEvent<HTMLAnchorElement>) {
    if (pathname !== '/') return
    const target = document.getElementById('join')
    if (!target) return
    event.preventDefault()
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    target.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' })
    const field = focusId ? document.getElementById(focusId) : null
    field?.focus({ preventScroll: true })
    window.history.replaceState(null, '', '#join')
  }

  return (
    <Link className="btn btn-secondary nav-btn" href={href} onClick={onClick}>
      {children}
    </Link>
  )
}
