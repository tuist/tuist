# Agent-facing marketing guides

Purpose-written English Markdown for all marketing landing pages: homepage, products, pricing, company, security, community, downloads, brand, and discovery directories. These are decision guides, not HTML extracts or instructions for an agent to follow. Legal and policy documents retain their original wording from `priv/marketing/pages`; the original community, openness, longevity, and security statements remain separately available.

## Content contract

- Explain the problem, how Tuist addresses it, fit, requirements, first steps, and limitations. Prefer concrete, qualified claims to slogans or performance promises.
- Whenever the content of an HTML marketing page changes, review and update its corresponding Markdown guide in the same change. Keep capabilities, toolchain support, prerequisites, availability, pricing guidance, limitations, and links consistent across both representations, while preserving the guide's concise, agent-oriented structure.
- Keep facts aligned with the HTML marketing pages and `priv/docs/en/`. Feature support differs by toolchain; selective testing currently requires generated Xcode projects, and runners are invite-only.
- Do not duplicate numeric pricing rates during the billing-model rollout. Link the live table and explain which usage and plan details to check.
- Use root-relative Markdown links. `TuistWeb.Utilities.MarketingMarkdown` expands them to the configured app URL.
- Only add English source content. Other localized marketing pages retain HTML conversion; do not silently replace translated pages with English guides.
- `home.md` maps to `/`; other filenames map to `/<filename>`. Files are embedded at compilation, with content and inventory changes triggering recompilation. They are not arbitrary filesystem downloads.

## Delivery and discovery

- `Accept: text/markdown` on the matching marketing URL selects the guide. Unknown marketing pages keep HTML-to-Markdown conversion.
- `/marketing-markdown` and `/marketing-markdown/<page>` provide header-free access, with one-hour public caching and no session cookies. `/marketing-markdown/source/<page>` serves original static-page Markdown, including the full statements that authored guides override.
- Blog, changelog, customer, and newsletter directory guides append up to 20 current entry links from their existing content modules. Individual entries retain their full content through HTML conversion; never freeze the changing catalog into an authored guide.
- HTML alternate links, HTTP `Link` headers, and `/llms.txt` advertise these documents.
- Redirects and errors must never be overwritten with product copy. On-premise marketing forwarding still applies.
- Do not extend this static mechanism to project dashboards. They need explicit, bounded data snapshots after authorization, with visibility rechecks and no shared caching.

## CDN rollout

Cloudflare does not generally use `Vary: Accept` to separate its cached representations. Only responses actually converted to Markdown send `Cloudflare-CDN-Cache-Control: no-store`, for both marketing and docs negotiation. HTML, redirects, errors, and unconverted bodies retain their existing CDN cache policies; browser caching remains governed by the existing Cache-Control and Vary headers. Explicit Markdown paths can be cached normally.

A cached HTML response can still reach a client requesting Markdown because a cache hit does not execute the origin plug. Use the advertised explicit Markdown URLs when representation must be reliable. Never configure an edge rule that ignores the converted response's `no-store` directive or stores Markdown under canonical HTML URLs.

Before release, check the active cache rules and purge any canonical marketing/docs cache entries that could contain previously negotiated Markdown through the normal deployment/operations process. After deployment, verify both request orders (HTML then Markdown, and Markdown then HTML) against the public edge, not only the origin:

```bash
curl -i https://tuist.dev/cache
curl -i -H 'Accept: text/markdown' https://tuist.dev/cache
curl -i https://tuist.dev/marketing-markdown/cache
```

Confirm ordinary browser requests always receive HTML, even after a Markdown request. When negotiation reaches the origin and returns Markdown, confirm `Cloudflare-CDN-Cache-Control: no-store` and that this representation is not an edge cache HIT. A Markdown-preferring request may receive cached HTML; this is an accepted limitation, not a reason to disable HTML caching. Confirm the explicit document is always Markdown with no Set-Cookie and retains its public cache policy. Apply the same origin-policy checks to docs negotiation. An Accept-aware cache key or request-level bypass rule is needed only to guarantee Markdown negotiation on the canonical URLs. No live CDN configuration is changed by these files.

## Validation

Run the focused Markdown negotiation, explicit marketing Markdown controller, MarketingMarkdown utility, and llms.txt controller suites. The utility suite checks local documentation links, full landing-page coverage, bounded directory discovery, original-statement access, and unchanged legal wording. Content received a Claude review for agent comprehension, feature distinctions, support matrices, current availability, and factual alignment.
