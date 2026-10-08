# Utilities (Web Layer)

This area owns web-layer utilities (query helpers, hashing).

## Responsibilities
- `LlmsTxt` builds and independently caches the `/llms.txt` index and `/llms-full.txt` documentation export from `Tuist.Docs.pages/0`. Keep exports English-only, deterministically ordered, and sourced from the same Markdown as individual docs endpoints.
- `SEO` owns query-free canonical URLs and informational project-route classification. `RobotsTxt` advertises both marketing and public-project sitemaps; never treat crawler policy as authorization.
- Provide query string manipulation utilities.
- Provide helpers like SHA and misc web utilities.
- Provide reusable content transformation helpers for the web layer, including HTML-to-Markdown conversion for agent-facing responses.
- Provide reusable response helpers for negotiated Markdown delivery.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
