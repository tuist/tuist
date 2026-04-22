# Docs Redirector

This directory contains the Cloudflare Worker that redirects the legacy `docs.tuist.dev` host to the current docs site under `tuist.dev`.

## Responsibilities
- Redirect `docs.tuist.dev/*` requests to `https://tuist.dev/:locale/docs/...`.
- Preserve supported locale prefixes when they still exist in the Phoenix docs app.
- Fall back unsupported legacy locale prefixes to English so old links do not redirect into dead routes.

## Boundaries
- Content-level docs redirects belong in `server/lib/tuist/docs/redirects.ex`.
- This worker should only handle host-level migration from the old docs site to the new one.

## Deployment
- Deploy with `wrangler deploy` from this directory.
- The production route is `docs.tuist.dev/*` in the `tuist.dev` Cloudflare zone.

## Related Context
- Infra overview: `infra/AGENTS.md`
- Server docs redirects: `server/lib/tuist/docs/redirects.ex`
