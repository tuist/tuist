# Cloudflare Configuration

These resources are reconciled by Flux through the Cloudflare operator. Editing git does not update the live zone in a local session, but merging into the reconciled source rolls changes out automatically.

## Crawlable public project roots

- `skip-sbfm-api-paths.yaml` skips only the Super Bot Fight Mode phase, not custom firewall rules or rate limits.
- The guarded GET/HEAD root clause identifies two non-empty path segments without plan-dependent regex. Wildcards match slashes, so the negative deeper-path guard is mandatory. Exclude sockets, authentication, operator routes, empty segments, encoded paths and scanner-shaped paths.
- Native Threads has a separate exact GET exemption for `/threads/socket/websocket`; Phoenix still authenticates its bearer subprotocol and authorizes subscriptions. Browser sockets and other `/threads/socket/` paths remain protected.
- The edge cannot know project visibility. Private-project authorization and anonymous filtered-root/deep-dashboard challenges stay at the origin. Public default overviews must use bounded read-through caching and meaningful initial HTML; deploy that server behavior before expanding the edge exemption.
- Signed `/open-graph-images/` URLs must be fetchable without JavaScript. Preserve signature validation and current visibility rechecks in the application. Deploy its origin rate limit (60 requests/minute per requester/route) before activating the image SBFM exemption; the public-page response-header limiter does not cover images.
- Re-enabling the legacy `public-dashboard-bot-protection` custom rule challenges unverified crawlers again even on cached roots. Its phase is not skipped by this exemption.
- Canonical project roots have no trailing slash. The guarded root clause deliberately excludes trailing slashes rather than accidentally exempting public-account paths.

## Crawlable documentation and Markdown

- GET/HEAD requests to legacy docs redirects, localized HTML/Markdown docs, `/marketing-markdown[/...]`, and crawler discovery/export endpoints skip SBFM. Locale docs roots already match the guarded two-segment clause; explicit trailing-slash prefixes cover their descendants. Keep those prefixes aligned with `Tuist.Locale`.
- Do not use a wildcard locale for docs: it would also match dashboards of a project named `docs`. Public content exemptions must not broaden the anonymous deep-dashboard bypass or skip custom firewall/rate-limit phases.
- Deeper public project dashboards retain the origin Turnstile gate after the scraper-driven ClickHouse overload. Removing SBFM alone does not make them machine-readable; opening them requires bounded data loading like the cached overview.

## Readable marketing pages

- `skip-sbfm-marketing-pages.yaml` is a separate rule so `skip-sbfm-api-paths.yaml` stays under Cloudflare's 4096-character expression limit. It permits GET and HEAD for published marketing routes; two-segment localized pages already match the project-root clause.
- The existing public-pages limiter counts only GET responses with `x-tuist-public: 1`; HEAD, docs and prefix fallthroughs are not necessarily counted. Resolve and validate these protection gaps before activation. Do not add data-backed live pages such as `/globe`.
- Do not add broad blog, changelog or newsletter prefixes, including localized prefixes: account handles may collide by case and historical project handles have not been audited. The sitemap clause limits the reserved `projects` project handle to a single XML segment; check historical data and normalization before activation. The existing `/docs/` prefix has a case-variant account collision risk. Articles and newsletter issues can remain challenged pending a safe rule.
- The rule was created in `read_only`. Activate it in a separate change only after the operator reports the expected proposed create and the server releases that mark feeds public and add the `/compare` and `/build-systems` guide pages are deployed; until then those two paths resolve as account pages.

## Validation

- Run `node --test infra/flux/cloudflare-config/test_skip_sbfm.mjs` from the repository root for complete-rule scope regression coverage of both SBFM skip rules (public docs/Markdown, marketing routes, project roots, protected dashboards, methods and existing machine paths). `.github/workflows/cloudflare-config-tests.yml` runs this credential-free check on pull requests and main changes.
- Render with `kubectl kustomize infra/flux/cloudflare-config` and validate the expression with Cloudflare during rollout. The local regression test checks wildcard/guard semantics, not Cloudflare's API parser or live zone state.
- Verify cookie-free docs/Markdown GET/HEAD requests, cookie-free marketing GET requests from an unverified client (for example `curl` with an agent user agent), a real search crawler and social unfurler after deployment, plus filtered/deeper challenges and edge rate limits. A spoofed Googlebot user agent does not demonstrate verified-bot behavior.
