import type { Metadata } from 'next'
import Link from 'next/link'
import { DraftNotice, PageHead, SupportEmail } from '@/components/PageHead'
import { site } from '@/lib/site'

export const metadata: Metadata = {
  title: 'Privacy policy',
  description: 'What PGYM collects, where it is kept, who can see it, and how to delete it.',
  alternates: { canonical: '/privacy' },
}

// Facts here come from pgym-design.md (data points, physique score rules) and
// pgym-architecture.md (components, storage, deletion). No legal draft existed
// when this page was built; see RESULT.md for the follow-up.

export default function PrivacyPage() {
  return (
    <div className="page">
      <div className="wrap">
        <PageHead label="Privacy" title="Privacy policy">
          <DraftNotice updated="15 November 2026" />
        </PageHead>
        <div className="prose">
          <p>
            PGYM is an iPhone app that turns a logged gym session into a timestamped proof card. This page says what
            we collect, why, where it is kept, who can see it and how you delete it. &ldquo;We&rdquo; means{' '}
            {site.operator}, which runs PGYM.
          </p>

          <h2>The short version</h2>
          <ul>
            <li>Your photos are private. Nobody sees them unless you share a card.</li>
            <li>The physique score is off unless you turn it on, needs you to be 18 or older, and only you see it.</li>
            <li>We do not sell your data and do not show ads.</li>
            <li>This website runs no analytics or advertising scripts.</li>
            <li>
              You can delete a photo, all photos or your whole account at any time, in the app or through{' '}
              <Link href="/delete-account">the delete account page</Link>.
            </li>
          </ul>

          <h2>What we collect</h2>
          <table>
            <thead>
              <tr>
                <th scope="col">What</th>
                <th scope="col">Why</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Account: email address, display name, sign-in method (Apple, Google or email)</td>
                <td>To sign you in and keep your data under your account</td>
              </tr>
              <tr>
                <td>Year of birth</td>
                <td>To keep the physique score for people 18 and older</td>
              </tr>
              <tr>
                <td>Settings: weekly goal, gym days, reminder time, units, time zone</td>
                <td>To count your weeks and send the reminder you asked for</td>
              </tr>
              <tr>
                <td>Training: routines, sessions, sets, weights, reps, times</td>
                <td>This is the app: your log, your bests, your streak</td>
              </tr>
              <tr>
                <td>Proof photos and the cards made from them</td>
                <td>To make and keep your proof cards. Location data is removed on the phone before upload</td>
              </tr>
              <tr>
                <td>Physique score and tip, only if you turn it on</td>
                <td>To show you the score and one training tip</td>
              </tr>
              <tr>
                <td>Agent tokens you create (we keep a one-way hash, never the token itself)</td>
                <td>To let your own AI agent read your data when you allow it</td>
              </tr>
              <tr>
                <td>App events: session started, finished, proof taken, card shared, reminder opened</td>
                <td>To see whether the app works and where it gets in the way. Not used for ads</td>
              </tr>
              <tr>
                <td>Waitlist: your email address, the date, and which button you used</td>
                <td>To send one email when PGYM is in the App Store</td>
              </tr>
            </tbody>
          </table>
          <p>
            We do not collect body weight, measurements, calories, heart rate, GPS location or Apple Health data.
          </p>

          <h2>Photos</h2>
          <p>
            The proof photo is taken in the app&apos;s own camera. It is uploaded to one private storage bucket, under
            a path that belongs to your account, with public access blocked and encryption at rest. Only you can
            request it, through short-lived signed links. A card leaves the app only when you share it, and then it
            goes where you send it.
          </p>

          <h2>The physique score</h2>
          <p>
            The physique score is off by default. You can turn it on only if you are 18 or older, and only after a
            screen that explains it. When it is on, the photo from each session is sent to a third-party AI vision
            model (Google&apos;s Gemini) to return a score from 0 to 100 and one training tip. The score is compared
            only with your own earlier scores. It never appears on the share card. Turning it off deletes every stored
            score and tip; your photos and proofs stay.
          </p>
          <p>The score is an AI estimate from one photo. It is not medical advice.</p>

          <h2>Your agent</h2>
          <p>
            You can create a token in the app that lets an AI agent of your choice read your PGYM data. The token only
            reads; it cannot change anything. Photos and the physique score are included only if you tick the photo
            permission. You can revoke a token at any time and it stops working at once. What your agent does with the
            data is between you and the agent&apos;s provider.
          </p>

          <h2>Where your data is kept</h2>
          <table>
            <thead>
              <tr>
                <th scope="col">Service</th>
                <th scope="col">What it holds</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Google Firebase (Authentication, Cloud Firestore, Cloud Functions)</td>
                <td>Sign-in, your account, settings, training data, scores</td>
              </tr>
              <tr>
                <td>Amazon Web Services S3</td>
                <td>Proof photos and cards</td>
              </tr>
              <tr>
                <td>Google Gemini API</td>
                <td>The session photo, only while it is scored, only if the score is on</td>
              </tr>
              <tr>
                <td>The website host</td>
                <td>This website and the waitlist form</td>
              </tr>
            </tbody>
          </table>
          <p>These providers process data for us under their own terms. We do not sell or rent your data to anyone.</p>

          <h2>How long we keep it</h2>
          <p>
            We keep your data while you have an account. When you delete a photo, it is removed from storage. When you
            delete your account, your account, photos, cards, sessions, sets, routines, scores, tips and agent tokens are
            deleted, and if you signed in with Apple, PGYM&apos;s access to your Apple ID is removed too. Cards you
            already shared stay wherever you posted them; we cannot remove those. Waitlist emails are kept until the
            launch email is sent, or until you ask us to remove yours.
          </p>

          <h2>Your choices and rights</h2>
          <ul>
            <li>See and export your data: Profile, then Privacy and data, then Export my data.</li>
            <li>Turn the physique score on or off at any time.</li>
            <li>Delete one photo, all photos or your account.</li>
            <li>
              Ask us anything about your data, or ask for a copy, a correction or deletion, at <SupportEmail subject="Privacy request" />.
            </li>
          </ul>
          <p>Depending on where you live, you may have further rights under local law. We will help you use them.</p>

          <h2>Children</h2>
          <p>
            PGYM is not for children. The physique score is never available to anyone under 18, and the analysis
            refuses any photo of someone who looks under 18.
          </p>

          <h2>Changes</h2>
          <p>If this policy changes, the new version is posted here with a new date.</p>

          <h2>Contact</h2>
          <p>
            <SupportEmail subject="Privacy" />
          </p>
        </div>
      </div>
    </div>
  )
}
