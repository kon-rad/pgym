/**
 * `PhysiqueRepo` on Firestore. The result lives on the session document as
 * `physique` (architecture note, "Data model"); there is no separate counter
 * document. The daily limit counts sessions whose `physique.analyzedAt` falls
 * in the user's local day and that reached the model (`physique.model` set).
 * Both queries are on a single field, so Firestore's automatic indexes serve
 * them.
 */
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import type { ClaimResult, PhysiqueRecord, PhysiqueRepo, PhysiqueSession, PhysiqueUser } from './physique';

/** Sessions read when looking for the last few scores; refusals in between are skipped. */
const RECENT_SCAN = 20;

function toDoc(r: PhysiqueRecord): Record<string, unknown> {
  const out: Record<string, unknown> = { analyzedAt: Timestamp.fromDate(r.analyzedAt) };
  if (r.score !== undefined) out.score = r.score;
  if (r.rawScore !== undefined) out.rawScore = r.rawScore;
  if (r.tip !== undefined) out.tip = r.tip;
  if (r.model !== undefined) out.model = r.model;
  if (r.refusedReason !== undefined) out.refusedReason = r.refusedReason;
  return out;
}

export class FirestorePhysiqueRepo implements PhysiqueRepo {
  constructor(private readonly db: Firestore) {}

  async getUser(uid: string): Promise<PhysiqueUser | null> {
    return (await this.db.doc(`users/${uid}`).get()).data() ?? null;
  }

  async getSession(uid: string, sessionId: string): Promise<PhysiqueSession | null> {
    return (await this.db.doc(`users/${uid}/sessions/${sessionId}`).get()).data() ?? null;
  }

  claim(uid: string, sessionId: string, opts: { dayStart: Date; limit: number; record: PhysiqueRecord }): Promise<ClaimResult> {
    const sRef = this.db.doc(`users/${uid}/sessions/${sessionId}`);
    const today = this.db
      .collection(`users/${uid}/sessions`)
      .where('physique.analyzedAt', '>=', Timestamp.fromDate(opts.dayStart));
    return this.db.runTransaction(async (tx) => {
      const [sSnap, todaySnap] = await Promise.all([tx.get(sRef), tx.get(today)]);
      const existing = sSnap.get('physique');
      if (!sSnap.exists || (existing !== undefined && existing !== null)) return 'already_analyzed';
      const used = todaySnap.docs.filter((d) => typeof d.get('physique.model') === 'string').length;
      if (used >= opts.limit) return 'daily_limit';
      tx.update(sRef, { physique: toDoc(opts.record) });
      return 'claimed';
    });
  }

  async recentRawScores(uid: string, excludeSessionId: string, count: number): Promise<number[]> {
    const snap = await this.db
      .collection(`users/${uid}/sessions`)
      .orderBy('physique.analyzedAt', 'desc')
      .limit(RECENT_SCAN)
      .get();
    const out: number[] = [];
    for (const d of snap.docs) {
      if (d.id === excludeSessionId) continue;
      const p = d.get('physique') as { score?: unknown; rawScore?: unknown } | undefined;
      const raw = typeof p?.rawScore === 'number' ? p.rawScore : p?.score;
      if (typeof raw === 'number' && Number.isFinite(raw)) out.push(raw);
      if (out.length >= count) break;
    }
    return out;
  }

  async write(uid: string, sessionId: string, record: PhysiqueRecord): Promise<void> {
    await this.db.doc(`users/${uid}/sessions/${sessionId}`).update({ physique: toDoc(record) });
  }
}
