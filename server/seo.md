# Public-page search indexing

## Scope and policy

Marketing pages and informational dashboards belonging to public projects may be indexed on the hosted production site. Private projects, link-shared previews in private projects, authentication screens, settings, connection flows, downloads, and raw timeline data remain non-indexable. Making a route crawlable never grants access to its data: existing HTTP and LiveView authorization checks remain authoritative.

The router's `public_project: true` metadata identifies informational dashboard pages. `robots_txt: false` keeps these paths out of the generated Disallow rules without declaring every private project public. The public-page header plug permits indexing only after resolving public visibility, and resets failed or redirected responses to `noindex, nofollow`. Non-production and self-hosted responses retain their existing noindex policy.

## Implemented technical checks

- **Server rendering:** Phoenix controllers and LiveView's disconnected render return HTML, including titles and metadata, without requiring JavaScript. Dashboard analytics still load asynchronously; their initial HTML may contain loading states. Do not invent metrics for crawlers or introduce a separate bot-only version of a page.
- **Canonical URLs:** marketing, docs, and dashboard layouts share one canonical URL builder. It uses the configured origin, strips query strings and fragments, and folds the dashboard overview and legacy Bazel invocation aliases into their preferred URLs. Social URL metadata uses the same URL.
- **Descriptions:** page-specific marketing descriptions are preserved. Project dashboards without explicit descriptions get the page title and project identity rather than Tuist's generic homepage description. Explicit descriptions remain authoritative.
- **Discovery:** `/sitemap.xml` covers marketing, documentation, and individual changelog entries. `/sitemap-projects.xml` indexes bounded `/sitemaps/projects/N.xml` files, each containing up to 1,000 public project roots. Internal navigation discovers dashboard sections and run details rather than enumerating an unbounded history of builds and tests. Detail pages are intentionally crawlable to cover public-project dashboards, but crawling them still incurs query costs; existing application and edge rate limits remain necessary. Accounts whose enforced single sign-on redirects anonymous requests are excluded; public accounts with anonymous access remain eligible. Project sitemaps are not cached, so a visibility change does not leave private projects in a stale response. Root entries intentionally omit `lastmod`: project-record updates are not a reliable content modification date.
- **Crawl policy:** `robots.txt` advertises both sitemaps and no longer blocks informational project HTML. Settings, downloads, and utility routes stay disallowed. `robots.txt` is not an authorization mechanism.
- **Structured data:** marketing already provides organization, website, product, article, breadcrumb, and FAQ markup where applicable. Only mark up FAQs actually visible on a page; do not fabricate FAQs on dashboards or promise FAQ rich results.

## Deployment checks and remaining editorial/performance work

These checks require the deployed site or human-owned external accounts. They are not implied by passing the source-level regression tests.

1. Submit both sitemap URLs in Google Search Console for the canonical production origin. Use URL Inspection on the homepage, a product page, a blog article, and public project build/test pages. Confirm anonymous access, the rendered HTML, canonical selection, and that no CDN rule replaces a successful response with a bot challenge.
2. Keep the public-page Turnstile gate and Cloudflare crawler policy aligned. When the application challenge flag is enabled, anonymous crawlers can be redirected to a non-indexable challenge. Any verified-bot exemption must rely on a trusted edge signal, never a spoofable User-Agent string. This change does not bypass the security gate.
3. Run a link crawl against the production origin and localized marketing routes. Check final destinations for missing pages and redirect chains. Existing renamed dashboard and documentation paths should remain compatible; prefer their canonical destinations in new links.
4. Audit visible page headings, especially dashboard overview/list pages. Several detail views already have a main heading, while some overview/list pages rely on card headings. Improve those semantics in the relevant page components without adding hidden keyword-stuffed headings or forcing duplicate H1s. One useful main heading is a content convention, not a guaranteed ranking signal.
5. Keep descriptive alternative text on meaningful images and empty alternative text on decorative images. Check compiled Markdown as well as templates. Prefer existing compact image derivatives; convert suitable raster artwork to WebP or AVIF when measurements justify it, not SVG icons or every social card indiscriminately.
6. Measure mobile and desktop Core Web Vitals on representative marketing and public dashboard pages. Set image dimensions where intrinsic sizes are known, reserve chart/media space, and inspect font and asynchronous-loading shifts. Aim for a Largest Contentful Paint under 2.5 seconds, Cumulative Layout Shift below 0.1, and Interaction to Next Paint below 200 milliseconds at the 75th percentile. A universal two-second guarantee cannot be established from source changes alone.
7. Review author profiles and article copy editorially. Preserve real authors and biographies; do not synthesize credibility signals. Backlinks and search rankings require ongoing human work and cannot be guaranteed by markup changes.

## Regression commands

From `server/`:

```sh
mix test test/tuist_web/utilities/seo_test.exs \
  test/tuist_web/controllers/project_sitemap_controller_test.exs \
  test/tuist_web/controllers/robots_txt_controller_test.exs \
  test/tuist_web/controllers/marketing_controller_test.exs \
  test/tuist_web/plugs/public_page_header_plug_test.exs
```
