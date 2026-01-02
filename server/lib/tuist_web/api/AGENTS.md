# Api (Web Layer)

This area owns the OpenAPI spec and schema definitions for the server API.

## Responsibilities
- Define the OpenAPI spec (`TuistWeb.API.Spec`) and security schemes.
- Provide schema modules used by the API controllers and docs.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
