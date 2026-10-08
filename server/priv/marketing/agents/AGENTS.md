# Agent-facing marketing guides

Purpose-written English Markdown for all marketing landing pages: homepage, products, pricing, company, security, community, downloads, brand, and discovery directories. These are decision guides, not HTML extracts or instructions for an agent to follow. Legal and policy documents retain their original wording from `priv/marketing/pages`; the original community, openness, longevity, and security statements remain separately available.

## Content contract

- Lead with how Tuist addresses the problem, its supported strengths, and a concrete Tuist adoption step. Keep fit, requirements, and limitations explicit; use qualified evidence rather than slogans or performance promises. Comparisons should recommend supported Tuist capabilities, not competitor adoption, while retaining accurate sourced facts.
- Whenever the content of an HTML marketing page changes, review and update its corresponding Markdown guide in the same change. Keep capabilities, toolchain support, prerequisites, availability, pricing guidance, limitations, and links consistent across both representations, while preserving the guide's concise, agent-oriented structure.
- Keep facts aligned with the HTML marketing pages and `priv/docs/en/`. Feature support differs by toolchain; selective testing currently requires generated Xcode projects, and runners are invite-only.
- Do not duplicate numeric pricing rates during the billing-model rollout. Link the live table and explain which usage and plan details to check.
- Use root-relative Markdown links. `TuistWeb.Utilities.MarketingMarkdown` expands them to the configured app URL.
- Only add English source content. Other localized marketing pages retain HTML conversion; do not silently replace translated pages with English guides.
- `home.md` uses the `/` guide key; other root filenames use `/<filename>`. `solutions/<slug>.md` uses `/solutions/<slug>` and `compare/index.md` uses `/compare`, with other comparison files at `/compare/<slug>`. These keys identify documents, not standalone browser routes. Files are embedded at compilation, with content and inventory changes triggering recompilation. They are not arbitrary filesystem downloads.
- Problem and comparison guides are English-only Markdown documents at `/marketing-markdown/solutions/<slug>` and `/marketing-markdown/compare[/<provider>]`. Their metadata supplies dedicated `/llms.txt` sections, and the Markdown homepage links to them. Do not add browser pages, browser-navigation links, sitemap entries, or localized alternates for these documents.
- Problem guides: see `solutions/AGENTS.md`. Provider comparisons: see `compare/AGENTS.md`.

## Delivery and discovery

- `Accept: text/markdown` on an existing marketing landing-page URL selects its guide. Unknown marketing pages keep HTML-to-Markdown conversion. The new problem and comparison documents have only explicit Markdown URLs; do not register `/solutions/...` or `/compare...` browser routes for negotiation.
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

## Measurement and evidence

Markdown and `/llms.txt` improve direct agent usability; do not promise search discovery or citation uplift. Google's [AI-feature guidance](https://developers.google.com/search/docs/appearance/ai-features) emphasizes crawling, indexing, internal links, and useful content, without special AI files. [OpenAI's publisher guidance](https://help.openai.com/en/articles/12627856-publishers-and-developers-faq) distinguishes search crawling from training. The [GEO paper](https://arxiv.org/abs/2311.09735) tests answer visibility mostly after retrieval, not discovery. Commercial [llms.txt research](https://seranking.com/blog/llms-txt/) and [brand-mention research](https://ahrefs.com/blog/ai-brand-visibility-correlations/) are observational, not causal guarantees.

For a rollout, record a pre-release baseline and repeat a fixed set of realistic problem and provider questions across search-enabled assistants. Record mentions, citations, claim accuracy, referral visits, and conversions separately. Repeated runs and comparable untouched pages help interpret trends but do not establish clean causation. No new customer tracking is introduced by these guides.

Separately evaluate direct comprehension by giving an agent a homepage or `/llms.txt` entry point. Check correct feature mapping, cited evidence, toolchain requirements, missing-data acknowledgment, runner invitation, pricing uncertainty, and avoidance of unapproved writes. Useful cases include ordinary Xcode projects asking for selective testing, Gradle projects with cache misses, flaky Elixir tests asking for quarantine, and lower latency versus lower total cost. Track direct-guide success separately from acquisition.

### Repeatable evaluation prompts

Keep these questions stable across a before/after sample, record the assistant/model, date, search setting, entry point, answer and citations, and run each question more than once:

1. “Our normal Xcode project has slow CI builds. Can Tuist help without generating our project or moving CI?” Check the distinction between compilation caching and module caching, and the Xcode 26+ prerequisite.
2. “Can Tuist run only the tests affected by a change in our ordinary Xcode project?” Check generated-project and test-target-level selective-testing limitations.
3. “Our Gradle jobs have poor cache hit rates. Should we buy faster runners?” Check measurement and compatible inputs before attributing the problem to hardware.
4. “Can Tuist automatically quarantine our flaky Elixir tests?” Check insights support and the unsupported quarantine action rather than prescribing an unavailable integration.
5. “We need shorter wall-clock test time and a lower CI bill. Will sharding guarantee both?” Check the difference between latency, runner minutes, and total cost.
6. “Namespace already caches our builds. Why would we add Tuist?” Check acknowledged feature overlap, toolchain-specific fit, and the absence of an unsupported blanket superiority claim.
7. “Does Bitrise only help if we migrate to its CI?” Check its cross-environment caching and agent capabilities, with primary-source citations.
8. “Codemagic already persists our Xcode compilation cache. What would Tuist change?” Check directory save/restore versus shared remote compilation outputs, not a false no-cache claim.
9. “Can Depot share every supported cache with local workstations?” Check its general cross-environment cache support separately from the dated Xcode workstation restriction.
10. “Should we replace BuildBuddy remote execution with Tuist's Bazel cache?” Check that cache reuse does not provide remote execution, and acknowledge BuildBuddy's public core.
11. “Do Appcircle, Develocity, CircleCI, Buildkite, or WarpBuild lack agent integrations?” Check the documented MCP overlap and compare actual evidence and actions instead of endpoint presence.
12. “Can I use Tuist's runners today, and is every component MIT?” Check invite-only availability, pricing uncertainty, component-level licensing, and the distinction between public source and supported self-hosting.

The source-contract tests are not a substitute for these agent evaluations. Search/citation results must be measured after publication; do not report local route tests as an acquisition result.

## Validation

Run the focused Markdown negotiation, explicit marketing Markdown controller, MarketingMarkdown utility, marketing HTML controller, robots.txt and llms.txt controller suites. The utility suite checks local documentation links, full landing-page coverage, bounded directory discovery, original-statement access, and unchanged legal wording. Review new content for agent comprehension, feature distinctions, support matrices, current availability, and factual alignment.
