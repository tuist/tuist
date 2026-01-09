# TuistWeb (Controllers, LiveView, API)

This directory contains the web interface: Phoenix controllers, LiveView, and API endpoints.

## Responsibilities
- HTTP routing, controllers, and API surface.
- LiveView components for the UI and marketing site.

## Boundaries
- Business logic should remain in `server/lib/tuist`.
- Frontend assets (JS/CSS) are in `server/assets`.

## Related Context (Downlinks)
- Api: `server/lib/tuist_web/api/AGENTS.md`
- Channels: `server/lib/tuist_web/channels/AGENTS.md`
- Components: `server/lib/tuist_web/components/AGENTS.md`
- Controllers: `server/lib/tuist_web/controllers/AGENTS.md`
- Errors: `server/lib/tuist_web/errors/AGENTS.md`
- Helpers: `server/lib/tuist_web/helpers/AGENTS.md`
- Live: `server/lib/tuist_web/live/AGENTS.md`
- Marketing: `server/lib/tuist_web/marketing/AGENTS.md`
- Plugs: `server/lib/tuist_web/plugs/AGENTS.md`
- Rate Limit: `server/lib/tuist_web/rate_limit/AGENTS.md`
- Utilities: `server/lib/tuist_web/utilities/AGENTS.md`

## Related Context
- Business logic: `server/lib/tuist/AGENTS.md`
- Assets pipeline: `server/assets/AGENTS.md`
