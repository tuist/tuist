# Utilities (Web Layer)

This area owns web-layer utilities (query helpers, hashing).

## Responsibilities
- Provide query string manipulation utilities.
- Provide helpers like SHA and misc web utilities.
- Generate runtime machine-readable responses such as `robots.txt` when they need to stay in sync with Phoenix routes.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
