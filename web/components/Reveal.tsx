'use client'

import { usePathname } from 'next/navigation'
import { useEffect } from 'react'

/**
 * Adds `is-in` to every [data-reveal] element as it scrolls into view, once.
 * Content is visible without JavaScript: the hidden start state only applies
 * under `html.js` (see globals.css), and Reduce Motion turns the motion off.
 * Runs again on every client-side navigation, since the layout stays mounted.
 */
export function RevealOnScroll() {
  const pathname = usePathname()
  useEffect(() => {
    const items = Array.from(document.querySelectorAll<HTMLElement>('[data-reveal]:not(.is-in)'))
    if (!('IntersectionObserver' in window)) {
      items.forEach((el) => el.classList.add('is-in'))
      return
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-in')
            observer.unobserve(entry.target)
          }
        }
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.12 },
    )
    items.forEach((el) => observer.observe(el))
    return () => observer.disconnect()
  }, [pathname])
  return null
}
