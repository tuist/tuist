# Plugs (Web Layer)

This area owns Plug middleware for request processing.

## Responsibilities
- Implement request/response middleware (auth, analytics, rate limiting).
- Handle cross-cutting response negotiation, such as alternate agent-friendly representations.
- Enforce cross-cutting concerns before controllers/LiveViews.
- `DeflateBodyReader` is the `Plug.Parsers` body reader in the endpoint: it inflates `Content-Encoding: deflate` (raw DEFLATE) request bodies, which the CLI sends for large test run uploads carrying code coverage, holding the decompressed size to the parser's `:length`.
- `SameOriginCSRFExemptionPlug` sets `:plug_skip_csrf_protection` when the browser proves the request is same-origin (`Sec-Fetch-Site: same-origin`, or `Origin` equal to `TuistWeb.RequestOrigin.from_conn/1`). It exists for POSTs submitted from CDN-cached marketing pages, whose embedded CSRF token belongs to another session. Pipe it ahead of `:protect_from_forgery` and only through scopes that contain nothing but the routes meant to be exempt; it does not filter by path.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
