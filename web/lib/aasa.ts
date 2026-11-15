// The apple-app-site-association document. The team ID and bundle ID come from the
// environment at request time; the Apple team ID is never committed.
//
// Paths: /proof/* is reserved for shared proofs (v1.1). Sign-in is email and password,
// so there is no sign-in link path; webcredentials lets iOS offer saved passwords
// for the site in the app's sign-in form.

export const PLACEHOLDER_TEAM_ID = 'TEAMID0000'
export const PLACEHOLDER_BUNDLE_ID = 'com.example.pgym'

export function appId(env: Record<string, string | undefined> = process.env): string {
  const team = env.APPLE_TEAM_ID?.trim() || PLACEHOLDER_TEAM_ID
  const bundle = env.IOS_BUNDLE_ID?.trim() || PLACEHOLDER_BUNDLE_ID
  return `${team}.${bundle}`
}

export function appleAppSiteAssociation(env: Record<string, string | undefined> = process.env) {
  const id = appId(env)
  return {
    applinks: {
      details: [
        {
          appIDs: [id],
          components: [{ '/': '/proof/*', comment: 'Shared proof cards' }],
        },
      ],
    },
    webcredentials: { apps: [id] },
  }
}
