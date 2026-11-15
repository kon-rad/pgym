import type { Metadata } from 'next'
import Link from 'next/link'
import { DraftNotice, PageHead, SupportEmail } from '@/components/PageHead'
import { site } from '@/lib/site'

export const metadata: Metadata = {
  title: 'Terms of use',
  description: 'The rules for using PGYM: your account, your photos, the physique score, and what PGYM is not.',
  alternates: { canonical: '/terms' },
}

export default function TermsPage() {
  return (
    <div className="page">
      <div className="wrap">
        <PageHead label="Terms" title="Terms of use">
          <DraftNotice updated="15 November 2026" />
        </PageHead>
        <div className="prose">
          <p>
            These terms are the agreement between you and {site.operator} (&ldquo;we&rdquo;) for using the PGYM app and
            this website. By creating an account you agree to them. Our{' '}
            <Link href="/privacy">privacy policy</Link> says what we do with your data.
          </p>

          <h2>1. Who can use PGYM</h2>
          <p>
            You need to be old enough to agree to these terms where you live. The physique score is only for people
            18 and older. You give your real year of birth when you sign up.
          </p>

          <h2>2. Your account</h2>
          <p>
            Keep your sign-in to yourself. You are responsible for what happens in your account, including what any
            agent you gave a token to reads. You can delete your account at any time; see{' '}
            <Link href="/delete-account">Delete your account</Link>.
          </p>

          <h2>3. Your photos and data</h2>
          <p>
            Your photos, sessions and cards are yours. You give us permission to store and process them only to run
            PGYM for you: to save them, make your cards, show them back to you and, if you turn it on, score them. We
            do not use them for anything else, and we do not sell them.
          </p>
          <p>
            Only take photos of yourself, or of people who agreed to be in them. Do not upload photos that show
            anyone under 18 without their parent&apos;s consent, or anything illegal, sexual or hateful.
          </p>

          <h2>4. Proof is proof</h2>
          <p>
            A proof card says you were there. Please keep it honest: do not try to fake the time, the proof number or
            the photo, and do not try to get around the in-app camera.
          </p>

          <h2>5. Not medical advice</h2>
          <p>
            PGYM is a training log and a motivation tool. It does not give medical, nutritional or health advice. The
            physique score is an AI estimate from one photo and can be wrong. The training tips are general. Check
            with a doctor before you start a new training plan, and stop if something hurts.
          </p>

          <h2>6. Agent access</h2>
          <p>
            You can give your own AI agent a token that reads your PGYM data. It cannot write or create proofs. You
            choose which agent gets a token, and you can revoke it at any time. Do not share a token with anyone you
            would not give your training log to.
          </p>

          <h2>7. Using PGYM fairly</h2>
          <p>
            Do not attack, overload or reverse the service&apos;s security, use other people&apos;s accounts, or scrape
            data that is not yours. The code is open source; using the code is covered by its licence on GitHub, not
            by these terms. Running your own copy does not give access to our servers or other users&apos; data.
          </p>

          <h2>8. Changes and availability</h2>
          <p>
            PGYM is new and will change. We may add, change or remove features. We will try to keep it running, but we
            cannot promise it is always available or free of bugs. If these terms change in a way that matters, we
            will say so in the app before the change applies.
          </p>

          <h2>9. Ending</h2>
          <p>
            You can stop using PGYM and delete your account at any time. We may suspend an account that breaks these
            terms, and will tell you why unless the law stops us.
          </p>

          <h2>10. Liability</h2>
          <p>
            PGYM is provided as it is. As far as the law allows, we are not liable for indirect losses, or for
            injuries from training. Nothing in these terms limits rights you have under consumer law that cannot be
            limited.
          </p>

          <h2>Contact</h2>
          <p>
            <SupportEmail subject="Terms" />
          </p>
        </div>
      </div>
    </div>
  )
}
