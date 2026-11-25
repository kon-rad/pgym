/**
 * The agent API's request and response schemas, in one place. The handlers in
 * api.ts validate input and shape output with these, and /v1/openapi.json is
 * generated from the same objects, so the description cannot drift from the
 * code. Field names and shapes follow the agent skill (copy/site/pgym-skill.md).
 */
import { z } from 'zod';

// ---------------------------------------------------------------------------
// Scopes and token management (callables)
// ---------------------------------------------------------------------------

export const SCOPES = ['read:profile', 'read:sessions', 'read:stats'] as const;
export const Scope = z.enum(SCOPES);
export type Scope = z.infer<typeof Scope>;

export const CreateAgentTokenInput = z.strictObject({
  name: z.string().trim().min(1).max(60),
  scopes: z.array(Scope).min(1).max(SCOPES.length * 2),
  /** Days until expiry, 1 to 365. Omitted: 90. `null`: no expiry. */
  expiresInDays: z.number().int().min(1).max(365).nullable().optional(),
});

export const RevokeAgentTokenInput = z.strictObject({
  tokenId: z.string().min(1).max(128),
});

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

export const PAGE_SIZE = 50;
export const RATE_LIMIT_PER_MINUTE = 60;
export const CARD_LINK_SEC = 10 * 60;

const Id = z
  .string()
  .regex(/^[A-Za-z0-9_-]{1,128}$/)
  .meta({ description: 'A document ID: letters, digits, `_` and `-`, at most 128 characters.' });
const Instant = z.iso.datetime({ offset: false }).meta({ description: 'ISO 8601 in UTC.' });
const WeekKey = z.string().regex(/^\d{4}-W\d{2}$/).meta({ description: 'ISO week, for example `2026-W46`.', example: '2026-W46' });
const Kg = z.number().meta({ description: 'Kilograms.' });
const Cursor = z.string().nullable().meta({ description: 'Pass as `cursor` to get the next page. `null` on the last page.' });

export const ERROR_CODES = [
  'invalid_request',
  'invalid_token',
  'insufficient_scope',
  'not_found',
  'method_not_allowed',
  'rate_limited',
  'server_error',
  'unavailable',
] as const;
export type ErrorCode = (typeof ERROR_CODES)[number];

export const ErrorBody = z
  .object({
    error: z.object({
      code: z.enum(ERROR_CODES).meta({ description: 'Stable, machine-readable. Branch on this, not on `message`.' }),
      message: z.string(),
      requiredScope: Scope.optional().meta({ description: 'Only on `insufficient_scope`.' }),
    }),
  })
  .meta({ description: 'Every error has this body.' });

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

const DateParam = z.iso.date().meta({ description: '`YYYY-MM-DD`, read in the owner\'s time zone. Inclusive.' });

export const RangeQuery = z.object({
  from: DateParam.optional(),
  to: DateParam.optional(),
  cursor: z.string().min(1).max(512).optional().meta({ description: '`nextCursor` from the previous page.' }),
});

export const IdParams = z.object({ id: Id });

// ---------------------------------------------------------------------------
// Responses
// ---------------------------------------------------------------------------

export const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;

export const Me = z.object({
  displayName: z.string().nullable(),
  units: z.enum(['kg', 'lb']).meta({ description: 'For display only. Every weight in this API is in kilograms.' }),
  timezone: z.string().meta({ description: 'IANA time zone. Weeks and query dates are read in it.' }),
  goalPerWeek: z.number().int().min(2).max(6).meta({ description: 'Sessions per week for the current week. A change applies from the next Monday.' }),
  gymDays: z.array(z.enum(WEEKDAYS)),
});

export const Stats = z.object({
  streakWeeks: z.number().int(),
  longestStreak: z.number().int(),
  passWeeks: z.number().int(),
  proofCount: z.number().int(),
  thisWeek: z.object({
    weekKey: WeekKey,
    sessions: z.number().int().meta({ description: 'Stamped sessions this week.' }),
    goal: z.number().int(),
  }),
  totalVolumeKg: Kg.meta({ description: 'All-time weight x reps over working sets of stamped sessions.' }),
});

const SessionStatus = z.enum(['finished', 'stamped']).meta({
  description: '`stamped` sessions have a photo, a server timestamp and a proof number, and count toward the week. `finished` ones do not.',
});

export const SessionSummary = z.object({
  id: Id,
  status: SessionStatus,
  routineName: z.string().nullable(),
  startedAt: Instant,
  durationSec: z.number().int().nullable(),
  timezone: z.string().nullable(),
  weekKey: WeekKey.nullable(),
  setCount: z.number().int(),
  totalVolumeKg: Kg,
  proofNumber: z.number().int().nullable(),
});

export const SessionList = z.object({
  sessions: z.array(SessionSummary).max(PAGE_SIZE),
  nextCursor: Cursor,
});

export const LoggedSet = z.object({
  n: z.number().int().nullable(),
  type: z.string().nullable().meta({ description: '`working`, `warmup`, `drop` or `failure`.' }),
  weightKg: Kg.nullable(),
  reps: z.number().int().nullable(),
  done: z.boolean(),
  rpe: z.number().nullable(),
});

export const SessionDetail = z.object({
  id: Id,
  status: SessionStatus,
  routineId: z.string().nullable(),
  routineName: z.string().nullable(),
  startedAt: Instant,
  endedAt: Instant.nullable(),
  stampedAt: Instant.nullable().meta({ description: 'Set by the server when the proof was stamped.' }),
  durationSec: z.number().int().nullable(),
  timezone: z.string().nullable(),
  weekKey: WeekKey.nullable(),
  proofNumber: z.number().int().nullable(),
  exercises: z.array(
    z.object({
      exerciseId: Id,
      name: z.string().nullable(),
      sets: z.array(LoggedSet),
    }),
  ),
  setCount: z.number().int(),
  totalVolumeKg: Kg,
  newBests: z.array(z.string()),
});

/** @deprecated Legacy schema retained for prelaunch fixture decoding. No route exposes it. */
export const CardLink = z.object({ url: z.url(), expiresAt: Instant });

export const ExerciseHistory = z.object({
  exerciseId: Id,
  name: z.string().nullable(),
  bestSet: z.object({ weightKg: Kg, reps: z.number().int() }).nullable().meta({ description: 'The set with the highest estimated one-rep max.' }),
  bestE1rmKg: Kg.meta({ description: 'Epley: weight x (1 + reps / 30).' }),
  lastPerformedAt: Instant.nullable(),
  history: z
    .array(
      z.object({
        sessionId: Id,
        startedAt: Instant,
        e1rmKg: Kg.meta({ description: 'Best estimated one-rep max in this session, working sets only.' }),
        sets: z.array(z.object({ type: z.string().nullable(), weightKg: Kg, reps: z.number().int() })),
      }),
    )
    .max(PAGE_SIZE)
    .meta({ description: 'Newest first. A page can hold fewer than 50 items while `nextCursor` is not null.' }),
  nextCursor: Cursor,
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

export interface Route {
  operationId: string;
  path: string; // OpenAPI form, for example /v1/sessions/{id}
  summary: string;
  description: string;
  scope: Scope;
  params?: z.ZodObject;
  query?: z.ZodObject;
  response: z.ZodType;
  /** Name under components.schemas. */
  responseName: string;
}

export const ROUTES = [
  {
    operationId: 'getMe',
    path: '/v1/me',
    summary: 'The owner\'s profile',
    description: 'Display name, units, time zone, weekly goal and gym days.',
    scope: 'read:profile',
    response: Me,
    responseName: 'Me',
  },
  {
    operationId: 'getStats',
    path: '/v1/stats',
    summary: 'Streak, counts and this week',
    description: 'Streak, longest streak, pass weeks, proof count, stamped sessions this week against the goal, and total weight lifted.',
    scope: 'read:stats',
    response: Stats,
    responseName: 'Stats',
  },
  {
    operationId: 'listSessions',
    path: '/v1/sessions',
    summary: 'Sessions, newest first',
    description: `Finished and stamped sessions, ${PAGE_SIZE} per page. Drafts are not listed.`,
    scope: 'read:sessions',
    query: RangeQuery,
    response: SessionList,
    responseName: 'SessionList',
  },
  {
    operationId: 'getSession',
    path: '/v1/sessions/{id}',
    summary: 'One session with every set',
    description: 'Structured workout data only. Local proof media and local AI insight are never exposed.',
    scope: 'read:sessions',
    params: IdParams,
    response: SessionDetail,
    responseName: 'SessionDetail',
  },
  {
    operationId: 'getExerciseHistory',
    path: '/v1/exercises/{id}/history',
    summary: 'One exercise over time',
    description: 'Every done set of one exercise in stamped sessions, newest first, with the best set and the estimated one-rep max per session.',
    scope: 'read:sessions',
    params: IdParams,
    query: RangeQuery,
    response: ExerciseHistory,
    responseName: 'ExerciseHistory',
  },
] as const satisfies readonly Route[];

export type RouteId = (typeof ROUTES)[number]['operationId'];

// ---------------------------------------------------------------------------
// OpenAPI 3.1
// ---------------------------------------------------------------------------

type JsonObject = Record<string, unknown>;

function jsonSchema(schema: z.ZodType, io: 'input' | 'output'): JsonObject {
  const out = z.toJSONSchema(schema, {
    target: 'draft-2020-12',
    io,
    // Responses may gain fields within v1; clients should ignore ones they do not know.
    override: (ctx) => {
      if (ctx.jsonSchema.additionalProperties === false) delete ctx.jsonSchema.additionalProperties;
    },
  }) as JsonObject;
  delete out.$schema;
  return out;
}

function parameters(where: 'path' | 'query', obj: z.ZodObject | undefined): JsonObject[] {
  if (!obj) return [];
  return Object.entries(obj.shape).map(([name, field]) => {
    const schema = jsonSchema(field as z.ZodType, 'input');
    const description = schema.description;
    delete schema.description;
    return {
      name,
      in: where,
      required: where === 'path' || !(field as z.ZodType).safeParse(undefined).success,
      ...(description ? { description } : {}),
      schema,
    };
  });
}

const errorRef = { $ref: '#/components/responses/Error' };
const rateHeaders = {
  'X-RateLimit-Limit': { $ref: '#/components/headers/X-RateLimit-Limit' },
  'X-RateLimit-Remaining': { $ref: '#/components/headers/X-RateLimit-Remaining' },
};

export function buildOpenApi(): JsonObject {
  const paths: JsonObject = {};
  const schemas: JsonObject = { Error: jsonSchema(ErrorBody, 'output') };

  for (const r of ROUTES as readonly Route[]) {
    const name = r.responseName;
    schemas[name] = jsonSchema(r.response, 'output');
    const responses: JsonObject = {
      200: {
        description: r.summary,
        headers: rateHeaders,
        content: { 'application/json': { schema: { $ref: `#/components/schemas/${name}` } } },
      },
      ...(r.params || r.query ? { 400: errorRef } : {}),
      401: errorRef,
      403: errorRef,
      ...(r.params ? { 404: errorRef } : {}),
      429: { $ref: '#/components/responses/RateLimited' },
      500: errorRef,
    };
    paths[r.path] = {
      get: {
        operationId: r.operationId,
        summary: r.summary,
        description: `${r.description}\n\nScope: \`${r.scope}\`.`,
        tags: ['v1'],
        security: [{ bearerAuth: [r.scope] }],
        'x-required-scope': r.scope,
        parameters: [...parameters('path', r.params), ...parameters('query', r.query)],
        responses,
      },
    };
  }

  paths['/v1/openapi.json'] = {
    get: {
      operationId: 'getOpenApi',
      summary: 'This document',
      description: 'Needs no token.',
      tags: ['v1'],
      security: [],
      responses: { 200: { description: 'The OpenAPI 3.1 description of this API.', content: { 'application/json': { schema: { type: 'object' } } } } },
    },
  };

  return {
    openapi: '3.1.0',
    info: {
      title: 'PGYM agent API',
      version: '1.0.0',
      summary: 'Read-only access to one PGYM user\'s own data, for that user\'s AI agent.',
      description: [
        'Send a personal access token as `Authorization: Bearer pgym_pat_...`. The owner creates it in the app (Profile, Agent access) and picks its scopes.',
        `Limits: ${RATE_LIMIT_PER_MINUTE} requests a minute per token; lists are paginated at ${PAGE_SIZE} with a cursor.`,
        'All weights are kilograms. All times are ISO 8601 in UTC. There is no write access.',
      ].join('\n\n'),
      license: { name: 'MIT', identifier: 'MIT' },
    },
    servers: [
      {
        url: 'https://{apiDomain}',
        variables: { apiDomain: { default: 'api.example.com', description: 'The PGYM API host.' } },
      },
    ],
    tags: [{ name: 'v1', description: 'Version 1, read-only.' }],
    paths,
    components: {
      securitySchemes: {
        bearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'pgym_pat_ followed by 40 letters and digits',
          description: `Scopes: ${SCOPES.map((s) => `\`${s}\``).join(', ')}.`,
        },
      },
      headers: {
        'X-RateLimit-Limit': { description: 'Requests allowed per minute for this token.', schema: { type: 'integer' } },
        'X-RateLimit-Remaining': { description: 'Requests left in the current minute.', schema: { type: 'integer' } },
      },
      responses: {
        Error: { description: 'An error. See `error.code`.', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } },
        RateLimited: {
          description: `More than ${RATE_LIMIT_PER_MINUTE} requests in a minute. Code \`rate_limited\`.`,
          headers: { 'Retry-After': { description: 'Seconds to wait.', schema: { type: 'integer' } }, ...rateHeaders },
          content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } },
        },
      },
      schemas,
    },
  };
}
