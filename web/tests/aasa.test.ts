import { describe, expect, it } from 'vitest'
import { appId, appleAppSiteAssociation, PLACEHOLDER_BUNDLE_ID, PLACEHOLDER_TEAM_ID } from '@/lib/aasa'

describe('apple-app-site-association', () => {
  it('builds the app ID from APPLE_TEAM_ID and IOS_BUNDLE_ID', () => {
    expect(appId({ APPLE_TEAM_ID: ' ABCDE12345 ', IOS_BUNDLE_ID: 'com.example.pgym' })).toBe(
      'ABCDE12345.com.example.pgym',
    )
  })

  it('falls back to placeholders, never a real team ID', () => {
    expect(appId({})).toBe(`${PLACEHOLDER_TEAM_ID}.${PLACEHOLDER_BUNDLE_ID}`)
  })

  it('claims only /proof/* for universal links and offers web credentials', () => {
    const doc = appleAppSiteAssociation({ APPLE_TEAM_ID: 'T', IOS_BUNDLE_ID: 'b' })
    expect(doc.applinks.details).toEqual([{ appIDs: ['T.b'], components: [{ '/': '/proof/*', comment: 'Shared proof cards' }] }])
    expect(doc.webcredentials).toEqual({ apps: ['T.b'] })
  })
})
