# Plugs (Web Layer)

This area owns Plug middleware for request processing.

## Responsibilities
- Implement request/response middleware (auth, analytics, rate limiting).
- Handle cross-cutting response negotiation, such as alternate agent-friendly representations.
- Enforce cross-cutting concerns before controllers/LiveViews.
- `DeflateBodyReader` is the `Plug.Parsers` body reader in the endpoint: it inflates `Content-Encoding: deflate` (raw DEFLATE) request bodies, which the CLI sends for large test run uploads carrying code coverage, holding the decompressed size to the parser's `:length`.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
