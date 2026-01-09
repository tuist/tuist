# TuistServer (Server Integration)

This module handles CLI integration with the Tuist Server APIs.

## Responsibilities
- Resolve server environment (base URL, OAuth client ID) with env var overrides.
- Provide cache storage factories and API clients for server-backed features.
- Map CLI actions to server operations (projects, previews, analytics, registry).

## Related Context
- Server codebase: `server/AGENTS.md`

## Invariants
- `TUIST_URL` overrides config URL and must be a valid URL.
- OAuth client ID defaults to a built-in value if not provided.
