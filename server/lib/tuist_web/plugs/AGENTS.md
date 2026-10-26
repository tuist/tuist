# Plugs (Web Layer)

This area owns Plug middleware for request processing.

## Responsibilities
- `ReportActorPlug` derives verified account/provenance from server authentication and accepts one bounded opaque actor header. Never resolve a claim to a user. `ReportPublishingAuthPlug` permits missing credentials only in the dedicated report-creation pipeline for structured Xcode, Gradle, Mix and test reports plus Bazel publishing sessions; invalid, blank, padded or duplicate supplied credentials fail, and supplied credentials discard stale authentication assignments before authentication. Browser cookies do not authenticate this pipeline. `ReportPublishingPlug` checks the default-off self-hosted instance startup setting and project/build-system compatibility with uncached project reads, then recursively bounds structure and schema-derived allowed keys, accepts the declared bounded Mix formatter runtime metadata for older SDKs without allowing arbitrary future request keys, rejects processing/artifact/history/shard references, and applies project quotas before anonymous schema validation. Repeat the protected-field and policy/allowlist checks after casting, treating cast date/time structs safely. `GradleReportPublishingPlug` is only an adapter to this shared policy. Fresh server-generated IDs must not mutate existing reports. Preserve normal authenticated authorization; never broaden archive, attachment, cache, read or admin permissions. Missing/wrong-system projects receive the same denial; authenticated lookup caching remains unchanged. Invalid optional actor headers are discarded with a generic warning, never allowed to suppress otherwise valid reports. Configured shared-quota failures fail closed; no broad build authorization exception is allowed.
- `PublicPageHeaderPlug` keeps public-response classification separate from indexing. Project indexing overrides noindex only for opted-in public project HTML on hosted production; redirects and failures reset it. Public-account indexing retains its separate existing policy. Settings and download routes must remain non-indexable even under a public project.
- `PublicPageChallengePlug` exempts only GET/HEAD public project roots with default/ignored tracking parameters. Use the private visibility marker set by `PublicPageHeaderPlug`, not a client header or user agent. The paired LiveView hook rechecks the actual URI on every patch; a root visit never grants verification for deeper dashboards.
- Implement request/response middleware (auth, analytics, rate limiting).
- `OriginWebhookPlug` handles `/webhooks/origin` ahead of body parsers, bounds raw bodies to 512 KB, verifies Cursor Ed25519 signatures over the hex SHA-256 digest, and routes the signed body rather than unsigned event headers. Lifecycle events are durably inserted into Oban before acknowledgment; signing-key outages return 503 so Origin retries.
- Handle cross-cutting response negotiation, such as alternate agent-friendly representations.
- `MarkdownNegotiationPlug` uses explicit Markdown Accept preferences, respects quality zero and HTML preference, and overrides only successful pages with authored marketing or original docs content. Never turn redirects/errors into guides. Only responses actually converted to Markdown disable Cloudflare CDN caching, for both marketing and docs negotiation. Preserve existing cache policies for HTML, redirects, errors, and other unconverted responses. An edge-cached HTML response can reach a Markdown-preferring client; explicit Markdown URLs are the reliable representation-specific path and remain cacheable.
- Enforce cross-cutting concerns before controllers/LiveViews.
- `DeflateBodyReader` is the `Plug.Parsers` body reader in the endpoint: it inflates `Content-Encoding: deflate` (raw DEFLATE) request bodies, which the CLI sends for large test run uploads carrying code coverage, holding the decompressed size to the parser's `:length`.
- `SameOriginCSRFExemptionPlug` sets `:plug_skip_csrf_protection` when the browser proves the request is same-origin (`Sec-Fetch-Site: same-origin`, or `Origin` equal to `TuistWeb.RequestOrigin.from_conn/1`). It exists for POSTs submitted from CDN-cached marketing pages, whose embedded CSRF token belongs to another session. Pipe it ahead of `:protect_from_forgery` and only through scopes that contain nothing but the routes meant to be exempt; it does not filter by path.

- `BrowserTelemetryPlug` owns the bounded same-origin `/-/faro/collect` gateway before the endpoint body parser. Validate signed sessions without refreshing cookies; never forward browser credentials to Alloy. Keep body/item/time limits, trusted Ray-ID handling and failure responses covered by tests.

## Boundaries
- Observability and Sentry plugs share `Tuist.Observability` normalization and replacement semantics. Set selected resources only from authoritative loaded structs, retaining auth separately. Clear absent keys and old cohorts on context changes; never copy headers, credentials or arbitrary conn assigns. Project ownership wins over inconsistent selected-account assigns.
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

## Authentication freshness

- Never cache authorization booleans across credentials: same-account credentials may have different scopes/project grants. Re-evaluate with the actual subject.
- Ordinary allowlisted API reads/uploads use dedicated `SubjectCache` snapshots with at most 60 seconds of non-sliding staleness and verified expiry checks. Resolve route policy before controller dispatch; other writes and runner-shell upgrades authenticate fresh by default. Credential creation/privilege changes also bypass resource-loader caches. Private loaders remain bounded; public project/account snapshots are reloaded before access, so privacy flips cannot inherit a cached public grant.
- Subject caching protects warm database reads, while immutable proof caching protects bcrypt. Observe real CI database/pool load; neither local tests nor mailbox independence establish production capacity.

- Proof-cache `UnavailableError` must render HTTP 503 in strict and cached authentication. Cachex-backed legacy subject fills return unavailable without retaining errors, and never bypass proof-cache failure guards with bcrypt.
