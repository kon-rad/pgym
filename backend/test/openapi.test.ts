import { describe, expect, it } from 'vitest';
import { openApiDocument } from '../src/api';
import { CardLink, ExerciseHistory, SessionDetail, SCOPES } from '../src/apiSchemas';
import { generateToken, hashToken, TOKEN_PATTERN } from '../src/agentTokens';

/** Needs no emulator: the document is built from the schemas alone. */
describe('OpenAPI document', () => {
  const doc = openApiDocument() as {
    openapi: string;
    paths: Record<string, { get: { operationId: string; security: Array<Record<string, string[]>>; parameters: Array<{ name: string; in: string }> } }>;
    components: { schemas: Record<string, unknown> };
  };

  it('validates as OpenAPI 3.1', async () => {
    const { Validator } = await import('@seriousme/openapi-schema-validator');
    const validator = new Validator();
    const result = await validator.validate(JSON.parse(JSON.stringify(doc)));
    expect(result.errors ?? []).toEqual([]);
    expect(result.valid).toBe(true);
    expect(validator.version).toBe('3.1');
  });

  it('lists the six endpoints with their scopes and parameters', () => {
    const expected: Record<string, [string, string, string[]]> = {
      '/v1/me': ['getMe', 'read:profile', []],
      '/v1/stats': ['getStats', 'read:stats', []],
      '/v1/sessions': ['listSessions', 'read:sessions', ['query:from', 'query:to', 'query:cursor']],
      '/v1/sessions/{id}': ['getSession', 'read:sessions', ['path:id']],
      '/v1/exercises/{id}/history': ['getExerciseHistory', 'read:sessions', ['path:id', 'query:from', 'query:to', 'query:cursor']],
      '/v1/sessions/{id}/card': ['getSessionCard', 'read:photos', ['path:id']],
    };
    for (const [path, [opId, scope, params]] of Object.entries(expected)) {
      const op = doc.paths[path]?.get;
      expect(op, path).toBeDefined();
      expect(op.operationId).toBe(opId);
      expect(op.security).toEqual([{ bearerAuth: [scope] }]);
      expect(op.parameters.map((p) => `${p.in}:${p.name}`)).toEqual(params);
    }
    expect(Object.keys(doc.paths).sort()).toEqual([...Object.keys(expected), '/v1/openapi.json'].sort());
  });

  it('describes physique as optional and private', () => {
    const session = doc.components.schemas.SessionDetail as { required: string[]; properties: Record<string, unknown> };
    expect(session.properties.physique).toBeDefined();
    expect(session.required).not.toContain('physique');
  });
});

describe('response schemas', () => {
  it('drop fields they do not name', () => {
    const out = CardLink.parse({ url: 'https://s3.test/k', expiresAt: '2026-11-18T18:10:00.000Z', key: 'users/x/sessions/y/card.jpg' });
    expect(out).toEqual({ url: 'https://s3.test/k', expiresAt: '2026-11-18T18:10:00.000Z' });
  });

  it('accept the timestamps Date.toISOString makes', () => {
    const r = ExerciseHistory.safeParse({
      exerciseId: 'bench-press',
      name: null,
      bestSet: null,
      bestE1rmKg: 0,
      lastPerformedAt: new Date('2026-11-18T18:00:00Z').toISOString(),
      history: [],
      nextCursor: null,
    });
    expect(r.success).toBe(true);
  });

  it('keep physique only when given', () => {
    const base = {
      id: 's1',
      status: 'stamped',
      routineId: null,
      routineName: null,
      startedAt: '2026-11-18T17:00:00.000Z',
      endedAt: null,
      stampedAt: null,
      durationSec: null,
      timezone: null,
      weekKey: null,
      proofNumber: null,
      exercises: [],
      setCount: 0,
      totalVolumeKg: 0,
      newBests: [],
    };
    expect(SessionDetail.parse(base)).not.toHaveProperty('physique');
    expect(SessionDetail.parse({ ...base, physique: { score: 50 } }).physique).toEqual({ score: 50 });
  });
});

describe('token format', () => {
  it('is pgym_pat_ plus 40 base62 characters, and hashes to 64 hex characters', () => {
    const t = generateToken();
    expect(t).toMatch(TOKEN_PATTERN);
    expect(hashToken(t)).toMatch(/^[0-9a-f]{64}$/);
    expect(SCOPES).toEqual(['read:profile', 'read:sessions', 'read:stats', 'read:photos']);
  });
});
