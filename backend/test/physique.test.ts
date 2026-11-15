import { describe, expect, it } from 'vitest';
import {
  DAILY_LIMIT,
  analyzePhysique,
  clampScore,
  cutTip,
  isAdult,
  localDayStart,
  parseModelReply,
  physiqueTaskId,
  readTask,
  smoothScore,
  tipAllowed,
  type PhysiqueDeps,
} from '../src/physique';
import { MODEL_REFUSAL_REASONS, PHYSIQUE_PROMPT, PHYSIQUE_RESPONSE_SCHEMA, TIP_MAX_CHARS } from '../src/physiquePrompt';
import { photoKey } from '../src/photoStore';
import { FakePhotoStore } from './helpers';
import { FakeVisionModel, MemoryPhysiqueRepo, RecordingLog } from './physiqueFakes';

const NOW = new Date('2026-11-18T18:00:00Z');
const UID = 'u1';

function setup(opts: { user?: Record<string, unknown>; model?: FakeVisionModel | null; now?: Date } = {}) {
  const repo = new MemoryPhysiqueRepo();
  const store = new FakePhotoStore();
  const model = opts.model === undefined ? new FakeVisionModel() : opts.model;
  const log = new RecordingLog();
  repo.setUser(UID, { physiqueConsent: true, birthYear: 1990, timezone: 'UTC', ...opts.user });
  const addSession = (id: string, fields: Record<string, unknown> = {}) => {
    repo.setSession(UID, id, { status: 'stamped', ...fields });
    store.put(photoKey(UID, id), 2_000_000);
  };
  const deps: PhysiqueDeps = { repo, store, model, now: () => opts.now ?? NOW, log };
  const run = (id: string) => analyzePhysique(deps, { uid: UID, sessionId: id });
  return { repo, store, model, log, deps, addSession, run };
}

const usable = (score: unknown, tip: unknown = 'Add a set of rows on pull days.') => ({ usable: true, refusedReason: null, score, tip });

describe('analyzePhysique: consent and age gate', () => {
  it('no consent means no model call and nothing written', async () => {
    const t = setup({ user: { physiqueConsent: false } });
    t.addSession('s1');
    expect(await t.run('s1')).toEqual({ status: 'skipped', reason: 'no_consent' });
    expect(t.model!.calls).toHaveLength(0);
    expect(t.repo.physiqueOf(UID, 's1')).toBeUndefined();
  });

  it('a missing consent field counts as no consent', async () => {
    const t = setup({ user: { physiqueConsent: undefined } });
    t.addSession('s1');
    expect(await t.run('s1')).toMatchObject({ reason: 'no_consent' });
    expect(t.model!.calls).toHaveLength(0);
  });

  it('a birth year under 18 means no model call', async () => {
    const t = setup({ user: { birthYear: 2010 } });
    t.addSession('s1');
    expect(await t.run('s1')).toEqual({ status: 'skipped', reason: 'under_18' });
    expect(t.model!.calls).toHaveLength(0);
    expect(t.repo.physiqueOf(UID, 's1')).toBeUndefined();
  });

  it('born 2008: still refused in 2026 (could be 17), allowed from 2027', async () => {
    const t = setup({ user: { birthYear: 2008 } });
    t.addSession('s1');
    expect(await t.run('s1')).toMatchObject({ reason: 'under_18' });
    expect(t.model!.calls).toHaveLength(0);

    const later = setup({ user: { birthYear: 2008 }, now: new Date('2027-01-01T12:00:00Z') });
    later.addSession('s1');
    expect(await later.run('s1')).toMatchObject({ status: 'scored' });
  });

  it('a missing birth year means no model call', async () => {
    const t = setup({ user: { birthYear: undefined } });
    t.addSession('s1');
    expect(await t.run('s1')).toMatchObject({ reason: 'under_18' });
    expect(t.model!.calls).toHaveLength(0);
  });

  it('skips unknown users, missing sessions, unstamped sessions and bad payloads without a model call', async () => {
    const t = setup();
    t.repo.setSession(UID, 'draft', { status: 'finished' });
    expect(await t.run('missing')).toMatchObject({ reason: 'no_session' });
    expect(await t.run('draft')).toMatchObject({ reason: 'not_stamped' });
    expect(await analyzePhysique(t.deps, { uid: 'nobody', sessionId: 's1' })).toMatchObject({ reason: 'no_user' });
    expect(await analyzePhysique(t.deps, { uid: '../x', sessionId: 's1' })).toMatchObject({ status: 'skipped' });
    expect(await analyzePhysique(t.deps, null)).toMatchObject({ status: 'skipped' });
    expect(t.model!.calls).toHaveLength(0);
  });
});

describe('analyzePhysique: scoring', () => {
  it('sends the fixed prompt, the schema and the session photo, then writes score, raw score, tip and model', async () => {
    const t = setup();
    t.addSession('s1');
    t.model!.reply(usable(64));
    const out = await t.run('s1');
    expect(out).toMatchObject({ status: 'scored', score: 64, rawScore: 64, tip: 'Add a set of rows on pull days.' });
    expect(t.model!.calls).toHaveLength(1);
    expect(t.model!.calls[0].prompt).toBe(PHYSIQUE_PROMPT);
    expect(t.model!.calls[0].responseSchema).toBe(PHYSIQUE_RESPONSE_SCHEMA);
    expect(t.model!.calls[0].mimeType).toBe('image/jpeg');
    expect(t.model!.calls[0].image.byteLength).toBe(2_000_000);
    expect(t.repo.physiqueOf(UID, 's1')).toEqual({
      score: 64,
      rawScore: 64,
      tip: 'Add a set of rows on pull days.',
      model: 'fake-vision-model',
      analyzedAt: NOW,
    });
  });

  it('a score of 140 is clamped to 100', async () => {
    const t = setup();
    t.addSession('s1');
    t.model!.reply(usable(140));
    expect(await t.run('s1')).toMatchObject({ status: 'scored', score: 100, rawScore: 100 });
    expect(t.repo.physiqueOf(UID, 's1')!.score).toBe(100);
  });

  it('a negative score is clamped to 0 and a fraction is rounded', async () => {
    const t = setup();
    t.addSession('s1');
    t.addSession('s2');
    t.model!.reply(usable(-12), usable(57.6));
    expect(await t.run('s1')).toMatchObject({ rawScore: 0 });
    expect(await t.run('s2')).toMatchObject({ rawScore: 58 });
  });

  it('the tip is cut to 140 characters', async () => {
    const long =
      'Add two sets of rows or pull-downs each week to keep back work level with your pressing, and finish each pull day with two sets of face pulls for the rear delts.';
    expect(long.length).toBeGreaterThan(TIP_MAX_CHARS);
    const t = setup();
    t.addSession('s1');
    t.model!.reply(usable(60, long));
    await t.run('s1');
    const tip = t.repo.physiqueOf(UID, 's1')!.tip!;
    expect(Array.from(tip).length).toBeLessThanOrEqual(TIP_MAX_CHARS);
    expect(long.startsWith(tip.slice(0, -1))).toBe(true);
    expect(tip.endsWith('.')).toBe(true);
  });

  it('a tip that breaks the copy rules is dropped and the score kept', async () => {
    for (const tip of ['Cut carbs to lean out.', 'Great job, keep going!', 'Add rows 💪', 'Your body fat looks low.']) {
      const t = setup(); // a fresh user each time, so the daily limit does not interfere
      t.addSession('s1');
      t.model!.reply(usable(60, tip));
      expect(await t.run('s1')).toMatchObject({ status: 'scored', tip: null });
      expect(t.repo.physiqueOf(UID, 's1')).not.toHaveProperty('tip');
      expect(t.repo.physiqueOf(UID, 's1')!.score).toBe(60);
    }
  });

  it('smooths against the last 3 raw scores, ignoring refusals and older ones', async () => {
    const t = setup();
    const at = (h: number) => new Date(NOW.getTime() - h * 3_600_000);
    t.repo.setSession(UID, 'old', { status: 'stamped', physique: { score: 10, rawScore: 10, model: 'm', analyzedAt: at(400) } });
    t.repo.setSession(UID, 'a', { status: 'stamped', physique: { score: 50, rawScore: 50, model: 'm', analyzedAt: at(300) } });
    t.repo.setSession(UID, 'b', { status: 'stamped', physique: { score: 55, rawScore: 60, model: 'm', analyzedAt: at(200) } });
    t.repo.setSession(UID, 'r', { status: 'stamped', physique: { refusedReason: 'unreadable', model: 'm', analyzedAt: at(150) } });
    t.repo.setSession(UID, 'c', { status: 'stamped', physique: { score: 70, rawScore: 70, model: 'm', analyzedAt: at(100) } });
    t.addSession('s1');
    t.model!.reply(usable(90));
    // (2 * 90 + 70 + 60 + 50) / 5 = 72
    expect(await t.run('s1')).toMatchObject({ status: 'scored', score: 72, rawScore: 90 });
    expect(t.repo.physiqueOf(UID, 's1')).toMatchObject({ score: 72, rawScore: 90 });
  });
});

describe('analyzePhysique: refusals and failures', () => {
  it('malformed model output writes refusedReason and no score', async () => {
    for (const bad of ['not json at all', '{"usable": true}', '{"usable": true, "score": "high"}', '{"score": 70}', '', '[1,2]']) {
      const t = setup();
      t.addSession('s1');
      t.model!.reply(bad);
      expect(await t.run('s1')).toEqual({ status: 'refused', refusedReason: 'failure', modelCalled: true });
      const p = t.repo.physiqueOf(UID, 's1')!;
      expect(p.refusedReason).toBe('failure');
      expect(p).not.toHaveProperty('score');
      expect(p).not.toHaveProperty('rawScore');
      expect(p).not.toHaveProperty('tip');
      expect(p.model).toBe('fake-vision-model');
    }
  });

  it('a model refusal writes its reason and no score', async () => {
    const t = setup();
    t.addSession('s1');
    t.model!.reply({ usable: false, refusedReason: 'several_people', score: 80, tip: 'x' });
    expect(await t.run('s1')).toMatchObject({ status: 'refused', refusedReason: 'several_people' });
    expect(t.repo.physiqueOf(UID, 's1')).toEqual({ refusedReason: 'several_people', model: 'fake-vision-model', analyzedAt: NOW });
  });

  it('an unknown refusal reason is stored as unreadable', async () => {
    const t = setup();
    t.addSession('s1');
    t.model!.reply({ usable: false, refusedReason: 'something else', score: null, tip: null });
    expect(await t.run('s1')).toMatchObject({ refusedReason: 'unreadable' });
  });

  it('a model error writes failure and is not retried', async () => {
    const t = setup();
    t.addSession('s1');
    t.model!.reply(new Error('Gemini returned HTTP 503'));
    expect(await t.run('s1')).toEqual({ status: 'refused', refusedReason: 'failure', modelCalled: true });
    expect(t.repo.physiqueOf(UID, 's1')).toMatchObject({ refusedReason: 'failure' });
    expect(await t.run('s1')).toMatchObject({ status: 'skipped', reason: 'already_analyzed' });
    expect(t.model!.calls).toHaveLength(1);
  });

  it('with no pinned model it writes failure without a call and without using a daily slot', async () => {
    const t = setup({ model: null });
    t.addSession('s1');
    expect(await t.run('s1')).toEqual({ status: 'refused', refusedReason: 'failure', modelCalled: false });
    expect(t.repo.physiqueOf(UID, 's1')).toEqual({ refusedReason: 'failure', analyzedAt: NOW });
  });

  it('a storage error throws (so the queue retries) and claims nothing', async () => {
    const t = setup();
    t.repo.setSession(UID, 's1', { status: 'stamped' }); // photo never uploaded
    await expect(t.run('s1')).rejects.toThrow();
    expect(t.repo.physiqueOf(UID, 's1')).toBeUndefined();
    expect(t.model!.calls).toHaveLength(0);
  });

  it('logs token counts but never the model text or the tip', async () => {
    const t = setup();
    t.addSession('s1');
    t.model!.reply(usable(61, 'Add hamstring curls on leg day.'));
    await t.run('s1');
    const text = JSON.stringify(t.log.lines);
    expect(text).toContain('inputTokens');
    expect(text).not.toContain('hamstring');
  });
});

describe('analyzePhysique: limits', () => {
  it('one analysis per session', async () => {
    const t = setup();
    t.addSession('s1');
    expect(await t.run('s1')).toMatchObject({ status: 'scored' });
    expect(await t.run('s1')).toEqual({ status: 'skipped', reason: 'already_analyzed' });
    expect(t.model!.calls).toHaveLength(1);
  });

  it('a fourth analysis in one day is refused', async () => {
    expect(DAILY_LIMIT).toBe(3);
    const t = setup();
    for (const id of ['s1', 's2', 's3', 's4']) t.addSession(id);
    expect(await t.run('s1')).toMatchObject({ status: 'scored' });
    expect(await t.run('s2')).toMatchObject({ status: 'scored' });
    expect(await t.run('s3')).toMatchObject({ status: 'scored' });
    expect(await t.run('s4')).toEqual({ status: 'refused', refusedReason: 'daily_limit', modelCalled: false });
    expect(t.model!.calls).toHaveLength(3);
    expect(t.repo.physiqueOf(UID, 's4')).toEqual({ refusedReason: 'daily_limit', analyzedAt: NOW });
  });

  it('model refusals and failures count toward the limit; limit refusals do not', async () => {
    const t = setup();
    for (const id of ['s1', 's2', 's3', 's4', 's5']) t.addSession(id);
    t.model!.reply({ usable: false, refusedReason: 'no_person', score: null, tip: null }, 'garbage');
    await t.run('s1'); // model refusal
    await t.run('s2'); // malformed
    expect(await t.run('s3')).toMatchObject({ status: 'scored' });
    expect(await t.run('s4')).toMatchObject({ refusedReason: 'daily_limit' });
    expect(await t.run('s5')).toMatchObject({ refusedReason: 'daily_limit' });
    expect(t.model!.calls).toHaveLength(3);
  });

  it("the day is the user's local day: a new day in their timezone frees the limit", async () => {
    // 2026-11-18T18:00Z is 10:00 in Los Angeles; 2026-11-19T07:59Z is still the 18th there, 08:00Z is the 19th.
    const repo = new MemoryPhysiqueRepo();
    const store = new FakePhotoStore();
    const model = new FakeVisionModel();
    repo.setUser(UID, { physiqueConsent: true, birthYear: 1990, timezone: 'America/Los_Angeles' });
    let clock = NOW;
    const deps: PhysiqueDeps = { repo, store, model, now: () => clock, log: new RecordingLog() };
    for (const id of ['a', 'b', 'c', 'd', 'e']) {
      repo.setSession(UID, id, { status: 'stamped' });
      store.put(photoKey(UID, id));
    }
    for (const id of ['a', 'b', 'c']) await analyzePhysique(deps, { uid: UID, sessionId: id });
    clock = new Date('2026-11-19T07:59:00Z');
    expect(await analyzePhysique(deps, { uid: UID, sessionId: 'd' })).toMatchObject({ refusedReason: 'daily_limit' });
    clock = new Date('2026-11-19T08:00:00Z');
    expect(await analyzePhysique(deps, { uid: UID, sessionId: 'e' })).toMatchObject({ status: 'scored' });
  });
});

describe('pure rules', () => {
  it('clampScore', () => {
    expect([clampScore(140), clampScore(-5), clampScore(49.5), clampScore(100), clampScore(0)]).toEqual([100, 0, 50, 100, 0]);
  });

  it('cutTip keeps short tips, collapses whitespace and never exceeds 140 code points', () => {
    expect(cutTip('  Add   rows.\n')).toBe('Add rows.');
    const exact = 'x'.repeat(140);
    expect(cutTip(exact)).toBe(exact);
    expect(Array.from(cutTip('y'.repeat(300))).length).toBe(140);
    expect(Array.from(cutTip('word '.repeat(60))).length).toBeLessThanOrEqual(140);
    const emoji = '🏋️'.repeat(100);
    expect(Array.from(cutTip(emoji)).length).toBeLessThanOrEqual(140);
  });

  it('tipAllowed follows the copy deck server check', () => {
    expect(tipAllowed('Add two sets of rows or pull-downs each week to keep back work level with your pressing.')).toBe(true);
    expect(tipAllowed('Rest 2 to 3 minutes between heavy sets so the next one gets your full effort.')).toBe(true);
    expect(tipAllowed('Train each muscle group twice a week rather than once for steadier progress.')).toBe(true);
    for (const bad of [
      'You are carrying extra fat around the waist. Cut carbs to lean out.',
      'Take creatine and a protein supplement after every session.',
      'It could be scoliosis, see a doctor.',
      'Great job. Keep crushing it!',
      'Start a bulk for size.',
      'Count your calories.',
      'Add rows 🔥',
      '',
    ]) {
      expect(tipAllowed(bad), bad).toBe(false);
    }
  });

  it('smoothScore', () => {
    expect(smoothScore(80, [])).toBe(80);
    expect(smoothScore(80, [60])).toBe(73); // (160 + 60) / 3
    expect(smoothScore(90, [70, 60, 50, 10])).toBe(72); // only the 3 newest
    expect(smoothScore(100, [100, 100, 100])).toBe(100);
  });

  it('parseModelReply', () => {
    expect(parseModelReply(JSON.stringify(usable(70, null)))).toEqual({ kind: 'usable', score: 70, tip: null });
    expect(parseModelReply(JSON.stringify({ usable: false, refusedReason: 'face_only', score: null, tip: null }))).toEqual({
      kind: 'refused',
      reason: 'face_only',
    });
    expect(parseModelReply(JSON.stringify(usable(Number.NaN)))).toMatchObject({ kind: 'malformed' });
    expect(parseModelReply(JSON.stringify(usable(null)))).toMatchObject({ kind: 'malformed' });
  });

  it('isAdult uses the year only and errs toward refusing', () => {
    expect(isAdult(2007, NOW)).toBe(true);
    expect(isAdult(2008, NOW)).toBe(false);
    expect(isAdult('1990', NOW)).toBe(false);
    expect(isAdult(1990.5, NOW)).toBe(false);
  });

  it('localDayStart', () => {
    expect(localDayStart(NOW, 'UTC').toISOString()).toBe('2026-11-18T00:00:00.000Z');
    expect(localDayStart(NOW, 'America/Los_Angeles').toISOString()).toBe('2026-11-18T08:00:00.000Z');
    expect(localDayStart(NOW, 'Not/AZone').toISOString()).toBe('2026-11-18T00:00:00.000Z');
  });

  it('the prompt names every refusal reason the schema allows and the 140-character tip rule', () => {
    for (const r of MODEL_REFUSAL_REASONS) expect(PHYSIQUE_PROMPT).toContain(`"${r}"`);
    expect(PHYSIQUE_RESPONSE_SCHEMA.properties.refusedReason.enum).toEqual([...MODEL_REFUSAL_REASONS]);
    expect(PHYSIQUE_RESPONSE_SCHEMA.required).toEqual(['usable', 'refusedReason', 'score', 'tip']);
    expect(PHYSIQUE_PROMPT).toContain('140 characters or fewer');
  });

  it('task payload and task ID', () => {
    expect(readTask({ uid: 'abc', sessionId: 's-1' })).toEqual({ uid: 'abc', sessionId: 's-1' });
    expect(readTask({ uid: 'a/b', sessionId: 's' })).toBeNull();
    expect(physiqueTaskId('abc', 's-1')).toBe('physique-abc-s-1');
  });
});
