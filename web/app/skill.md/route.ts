import { skillFile } from '@/lib/content'

// The skill file for AI agents, served as plain markdown with its frontmatter
// (name, description) so an agent can load it as a skill. Copy: content/skill.md,
// from the vault's copy/site/pgym-skill.md. Placeholders are filled from the
// environment at build time (see lib/content.ts).

export const dynamic = 'force-static'

export function GET() {
  return new Response(skillFile(), {
    headers: {
      'content-type': 'text/markdown; charset=utf-8',
      'cache-control': 'public, max-age=3600',
    },
  })
}
