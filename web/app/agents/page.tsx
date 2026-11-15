import type { Metadata } from 'next'
import { MarkdownPage } from '@/components/MarkdownPage'
import { loadPage } from '@/lib/content'

// Copy: content/agents.md, from the vault's copy/site/pgym-agents-page.md, unchanged.
const page = loadPage('agents.md')

export const dynamic = 'force-static'

export const metadata: Metadata = {
  title: page.title,
  description: page.description,
  alternates: { canonical: '/agents' },
}

export default function AgentsPage() {
  return (
    <MarkdownPage label="Agents" page={page}>
      <p className="open-links">
        <a className="btn btn-secondary" href="/skill.md">
          Read the skill file
        </a>
      </p>
    </MarkdownPage>
  )
}
