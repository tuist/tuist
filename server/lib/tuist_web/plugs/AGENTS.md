# Plugs (Web Layer)

This area owns Plug middleware for request processing.

## Responsibilities
- Implement request/response middleware (auth, analytics, rate limiting).
- Handle cross-cutting response negotiation, such as alternate agent-friendly representations.
- Enforce cross-cutting concerns before controllers/LiveViews.
- `PublicPageHeaderPlug` marks public visibility for edge rate limiting without
  changing the dashboard's `noindex, nofollow` policy. Public project/account
  pages remain disallowed in robots.txt.
- `PublicPageChallengePlug` gates anonymous dashboard entry before LiveView
  queries; the paired live hook gates connected mounts. Managed Helm values
  enable it through `server.publicPageChallenge.enabled`.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
