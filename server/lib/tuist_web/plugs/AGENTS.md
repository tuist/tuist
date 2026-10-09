# Plugs (Web Layer)

This area owns Plug middleware for request processing.

## Responsibilities
- `PublicPageHeaderPlug` keeps public-response classification separate from indexing. Project indexing overrides noindex only for opted-in public project HTML on hosted production; redirects and failures reset it. Public-account indexing retains its separate existing policy. Settings and download routes must remain non-indexable even under a public project.
- `PublicPageChallengePlug` exempts only GET/HEAD public project roots with default/ignored tracking parameters. Use the private visibility marker set by `PublicPageHeaderPlug`, not a client header or user agent. The paired LiveView hook rechecks the actual URI on every patch; a root visit never grants verification for deeper dashboards.
- Implement request/response middleware (auth, analytics, rate limiting).
- Handle cross-cutting response negotiation, such as alternate agent-friendly representations.
- `MarkdownNegotiationPlug` uses explicit Markdown Accept preferences, respects quality zero and HTML preference, and overrides only successful pages with authored marketing or original docs content. Never turn redirects/errors into guides. Only responses actually converted to Markdown disable Cloudflare CDN caching, for both marketing and docs negotiation. Preserve existing cache policies for HTML, redirects, errors, and other unconverted responses. An edge-cached HTML response can reach a Markdown-preferring client; explicit Markdown URLs are the reliable representation-specific path and remain cacheable.
- Enforce cross-cutting concerns before controllers/LiveViews.
- `DeflateBodyReader` is the `Plug.Parsers` body reader in the endpoint: it inflates `Content-Encoding: deflate` (raw DEFLATE) request bodies, which the CLI sends for large test run uploads carrying code coverage, holding the decompressed size to the parser's `:length`.
- `SameOriginCSRFExemptionPlug` sets `:plug_skip_csrf_protection` when the browser proves the request is same-origin (`Sec-Fetch-Site: same-origin`, or `Origin` equal to `TuistWeb.RequestOrigin.from_conn/1`). It exists for POSTs submitted from CDN-cached marketing pages, whose embedded CSRF token belongs to another session. Pipe it ahead of `:protect_from_forgery` and only through scopes that contain nothing but the routes meant to be exempt; it does not filter by path.

- `BrowserTelemetryPlug` owns the bounded same-origin `/-/faro/collect` gateway before the endpoint body parser. Validate signed sessions without refreshing cookies; never forward browser credentials to Alloy. Keep body/item/time limits, trusted Ray-ID handling and failure responses covered by tests.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- Do not cache authenticated subjects or successful authorization decisions. Credential and permission revocation must apply on the next request regardless of which web node receives it.
