# Cloudflare Configuration

These resources are reconciled by Flux through the Cloudflare operator. Editing git does not update the live zone in a local session, but merging into the reconciled source rolls changes out automatically.

## Crawlable public project roots

- `skip-sbfm-api-paths.yaml` skips only the Super Bot Fight Mode phase, not custom firewall rules or rate limits.
- The guarded GET/HEAD root clause identifies two non-empty path segments without plan-dependent regex. Wildcards match slashes, so the negative deeper-path guard is mandatory. Exclude sockets, authentication, operator routes, empty segments, encoded paths and scanner-shaped paths.
- The edge cannot know project visibility. Private-project authorization and anonymous filtered-root/deep-dashboard challenges stay at the origin. Public default overviews must use bounded read-through caching and meaningful initial HTML; deploy that server behavior before expanding the edge exemption.
- Signed `/open-graph-images/` URLs must be fetchable without JavaScript. Preserve signature validation and current visibility rechecks in the application. Deploy its origin rate limit (60 requests/minute per requester/route) before activating the image SBFM exemption; the public-page response-header limiter does not cover images.
- Re-enabling the legacy `public-dashboard-bot-protection` custom rule challenges unverified crawlers again even on cached roots. Its phase is not skipped by this exemption.
- Canonical project roots have no trailing slash. The guarded root clause deliberately excludes trailing slashes rather than accidentally exempting public-account paths.

## Crawlable documentation and Markdown

- GET/HEAD requests to legacy docs redirects, localized HTML/Markdown docs, `/marketing-markdown[/...]`, and crawler discovery/export endpoints skip SBFM. Locale docs roots already match the guarded two-segment clause; explicit trailing-slash prefixes cover their descendants. Keep those prefixes aligned with `Tuist.Locale`.
- Do not use a wildcard locale for docs: it would also match dashboards of a project named `docs`. Public content exemptions must not broaden the anonymous deep-dashboard bypass or skip custom firewall/rate-limit phases.
- Deeper public project dashboards retain the origin Turnstile gate after the scraper-driven ClickHouse overload. Removing SBFM alone does not make them machine-readable; opening them requires bounded data loading like the cached overview.

## Validation

- Run `python3 infra/flux/cloudflare-config/test_skip_sbfm.py` from the repository root for complete-rule scope regression coverage (public docs/Markdown, project roots, protected dashboards, methods and existing machine paths). `.github/workflows/cloudflare-config-tests.yml` runs this credential-free check on pull requests and main changes.
- Render with `kubectl kustomize infra/flux/cloudflare-config` and validate the expression with Cloudflare during rollout. The local regression test checks wildcard/guard semantics, not Cloudflare's API parser or live zone state.
- Verify cookie-free docs/Markdown GET/HEAD requests, a real search crawler and social unfurler after deployment, plus filtered/deeper challenges and edge rate limits. A spoofed Googlebot user agent does not demonstrate verified-bot behavior.
