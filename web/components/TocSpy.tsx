'use client'

import { useEffect } from 'react'

/**
 * Marks the contents link of the section being read with aria-current, so the
 * sticky contents column shows it in Chalk. Without JavaScript every link stays
 * Steel and still works.
 */
export function TocSpy({ ids }: { ids: string[] }) {
  const key = ids.join(' ')
  useEffect(() => {
    const list = key.split(' ')
    const sections = list.map((id) => document.getElementById(id)).filter((el): el is HTMLElement => el !== null)
    if (!sections.length || !('IntersectionObserver' in window)) return
    const links = new Map(
      list.map((id) => [id, document.querySelector<HTMLAnchorElement>(`.doc-toc a[href="#${CSS.escape(id)}"]`)]),
    )
    const visible = new Set<string>()
    const mark = () => {
      const current = list.find((id) => visible.has(id))
      for (const [id, link] of links) {
        if (!link) continue
        if (id === current) link.setAttribute('aria-current', 'location')
        else link.removeAttribute('aria-current')
      }
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) visible.add(e.target.id)
          else visible.delete(e.target.id)
        }
        mark()
      },
      { rootMargin: '-15% 0px -60% 0px' },
    )
    sections.forEach((s) => observer.observe(s))
    return () => observer.disconnect()
  }, [key])
  return null
}
