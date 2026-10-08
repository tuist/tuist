# Utilities (Web Layer)

This area owns web-layer utilities (query helpers, hashing).

## Responsibilities
- `LlmsTxt` builds and independently caches the `/llms.txt` index and `/llms-full.txt` documentation export from `Tuist.Docs.pages/0`. Keep exports English-only, deterministically ordered, and sourced from the same Markdown as individual docs endpoints.
- `SEO` owns query-free canonical URLs and informational project-route classification. `RobotsTxt` advertises both marketing and public-project sitemaps; never treat crawler policy as authorization.
- Provide query string manipulation utilities.
- Provide helpers like SHA and misc web utilities.
- Provide reusable content transformation helpers for the web layer, including HTML-to-Markdown conversion for agent-facing responses.
- Provide reusable response helpers for negotiated Markdown delivery.
- `MarketingMarkdown` embeds English landing-page decision guides from `priv/marketing/agents` and original static-page sources from `priv/marketing/pages`, expands links against the configured app URL, and supplies explicit alternate paths. It appends bounded live-content directories; legal wording stays unchanged and original company statements remain separately accessible. Keep `/llms.txt` product discovery aligned with current marketing routes and those alternates. The nested `solutions` and `compare` guides also generate public English-only HTML from the same source; `public_pages/0` supplies the route, sitemap, and `/llms.txt` inventories. Preserve browser-link conversion, table rendering, and exclusion of intent files.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
