import type { ClaimResult, Logger, PhysiqueRecord, PhysiqueRepo, PhysiqueSession, PhysiqueUser } from '../src/physique';
import type { VisionModel, VisionRequest, VisionResponse } from '../src/visionModel';

/** In-memory PhysiqueRepo with the same rules as FirestorePhysiqueRepo. */
export class MemoryPhysiqueRepo implements PhysiqueRepo {
  readonly users = new Map<string, PhysiqueUser>();
  /** Keyed `${uid}/${sessionId}`. */
  readonly sessions = new Map<string, PhysiqueSession & { physique?: PhysiqueRecord }>();

  private key(uid: string, sessionId: string) {
    return `${uid}/${sessionId}`;
  }

  setUser(uid: string, u: PhysiqueUser): void {
    this.users.set(uid, u);
  }

  setSession(uid: string, sessionId: string, s: PhysiqueSession & { physique?: PhysiqueRecord }): void {
    this.sessions.set(this.key(uid, sessionId), s);
  }

  physiqueOf(uid: string, sessionId: string): PhysiqueRecord | undefined {
    return this.sessions.get(this.key(uid, sessionId))?.physique;
  }

  private sessionsOf(uid: string) {
    return [...this.sessions.entries()].filter(([k]) => k.startsWith(`${uid}/`)).map(([k, s]) => ({ id: k.slice(uid.length + 1), s }));
  }

  async getUser(uid: string) {
    return this.users.get(uid) ?? null;
  }

  async getSession(uid: string, sessionId: string) {
    return this.sessions.get(this.key(uid, sessionId)) ?? null;
  }

  async claim(uid: string, sessionId: string, opts: { dayStart: Date; limit: number; record: PhysiqueRecord }): Promise<ClaimResult> {
    const s = this.sessions.get(this.key(uid, sessionId));
    if (!s || s.physique) return 'already_analyzed';
    const used = this.sessionsOf(uid).filter(
      ({ s: o }) => o.physique && o.physique.analyzedAt >= opts.dayStart && typeof o.physique.model === 'string',
    ).length;
    if (used >= opts.limit) return 'daily_limit';
    s.physique = { ...opts.record };
    return 'claimed';
  }

  async recentRawScores(uid: string, excludeSessionId: string, count: number): Promise<number[]> {
    return this.sessionsOf(uid)
      .filter(({ id, s }) => id !== excludeSessionId && s.physique)
      .sort((a, b) => b.s.physique!.analyzedAt.getTime() - a.s.physique!.analyzedAt.getTime())
      .map(({ s }) => s.physique!.rawScore ?? s.physique!.score)
      .filter((n): n is number => typeof n === 'number')
      .slice(0, count);
  }

  async write(uid: string, sessionId: string, record: PhysiqueRecord): Promise<void> {
    const s = this.sessions.get(this.key(uid, sessionId));
    if (!s) throw new Error('no session');
    s.physique = { ...record };
  }
}

/** A VisionModel that returns canned replies and records every call. Never touches the network. */
export class FakeVisionModel implements VisionModel {
  readonly modelId = 'fake-vision-model';
  readonly calls: VisionRequest[] = [];
  private queue: Array<string | Error> = [];

  constructor(private fallback: string | Error = JSON.stringify({ usable: true, refusedReason: null, score: 60, tip: 'Add a set of rows on pull days.' })) {}

  /** Replies for the next calls, in order; afterwards the fallback. */
  reply(...replies: Array<string | object | Error>): this {
    this.queue.push(...replies.map((r) => (typeof r === 'string' || r instanceof Error ? r : JSON.stringify(r))));
    return this;
  }

  async analyze(req: VisionRequest): Promise<VisionResponse> {
    this.calls.push(req);
    const next = this.queue.shift() ?? this.fallback;
    if (next instanceof Error) throw next;
    return { text: next, usage: { inputTokens: 1290, outputTokens: 60 }, finishReason: 'STOP' };
  }
}

export class RecordingLog implements Logger {
  readonly lines: Array<{ level: 'info' | 'warn'; message: string; data?: Record<string, unknown> }> = [];
  info(message: string, data?: Record<string, unknown>) {
    this.lines.push({ level: 'info', message, data });
  }
  warn(message: string, data?: Record<string, unknown>) {
    this.lines.push({ level: 'warn', message, data });
  }
}
