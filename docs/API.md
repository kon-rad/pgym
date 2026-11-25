# PGYM agent API v1

The API is read-only structured workout access for one user's own agent. It never returns local proof photos, rendered cards or transient AI insights.

- Base URL: `https://[API-DOMAIN]/v1`
- OpenAPI 3.1: `GET /v1/openapi.json`
- Authentication: `Authorization: Bearer pgym_pat_...`
- Tokens are stored only as SHA-256 hashes and can be revoked immediately.
- Page size: 50; rate limit: 60 requests per minute per token.

## Scopes

| Scope | Reads |
|---|---|
| `read:profile` | Display name, units, timezone, weekly goal and gym days |
| `read:stats` | Weekly streak, longest streak, pass weeks, proof count, current week and total volume |
| `read:sessions` | Session list, session sets and exercise history |

There is no `read:photos` scope and no write scope.

## Endpoints

| Endpoint | Scope |
|---|---|
| `GET /v1/me` | `read:profile` |
| `GET /v1/stats` | `read:stats` |
| `GET /v1/sessions` | `read:sessions` |
| `GET /v1/sessions/{id}` | `read:sessions` |
| `GET /v1/exercises/{id}/history` | `read:sessions` |
| `GET /v1/openapi.json` | none |

Session responses include structured workout data, the server timestamp and proof number. Local media and local AI insight are intentionally absent. Query dates are inclusive `YYYY-MM-DD` in the owner's timezone. Weights are kilograms. Times are ISO 8601 UTC.

Errors use `{ "error": { "code": "...", "message": "..." } }` with stable codes: `invalid_request`, `invalid_token`, `insufficient_scope`, `not_found`, `method_not_allowed`, `rate_limited`, `server_error`, and `unavailable`.
