# Atlas public documentation

Implemented on 2 October 2026 as part of the Atlas decoupling work.

## Publication scope

Only the overview is public while decoupling continues. Unfinished installation, configuration, integration, and workspace guides remain unpublished under `plans/atlas-documentation-drafts/`. Their old public and Markdown addresses return missing-page responses.

The overview leads with “Your operations, on auto-pilot” and describes how Atlas grew from Tuist’s need to maximize the value each employee could create. A single Noora information alert explains that Atlas is a work in progress and that its implementation is being decoupled from decisions made for Tuist.

## Entry points and rendering

`/docs` serves documentation without sign-in. Signed-out requests to `/` redirect to `/docs`; signed-in requests retain the dashboard. Other application routes retain their authentication requirements. Documentation neither fetches user records nor starts a live application session.

Source Markdown lives in `atlas/priv/docs/`, is tracked as a compilation resource, and is compiled into the release. Unknown pages return a missing-page response.

## Layout and components

The separate documentation asset bundle adapts Tuist’s root layout, navigation, page-copy dropdown, theme controls, code snippets, and table styles. Noora provides the alert, buttons, icons, dropdown behavior, and table scrolling. Blue accents and a recolored Atlas mark give the documentation its own identity without changing the dashboard palette.

Desktop and mobile headers link to Atlas’s GitHub source and sign-in page. Mobile navigation supports Escape and restores focus. The overview has no section headings, so its empty table of contents is omitted. The copy-page control remains available on desktop and mobile.

The Markdown renderer retains Noora alerts, inline-code treatment, fenced snippets with clipboard feedback, and horizontally scrolling Noora tables for future pages. Table verification uses an unpublished fixture; the configuration page remains unavailable publicly.

## Markdown and social previews

`Accept: text/markdown` returns the source at the same public address. Quality values determine whether Markdown or HTML is preferred. `Vary: Accept` separates cached representations. `/docs-markdown` serves plain text for the dropdown’s open-source action.

The overview publishes social preview metadata. `mix atlas.docs.images` regenerates its 1920 × 1080 image using isolated [headless Chrome](https://developer.chrome.com/docs/chromium/headless). The product image is committed under `atlas/priv/static/images/docs/`, so production requests need no browser or image-storage dependency.

## Crawler protection

Public documentation emits `x-tuist-public: 1`, matching the existing zone-wide rules in `infra/flux/cloudflare-config/public-pages-rate-limit.yaml` and `verified-crawlers-rate-limit.yaml`: 60 counted requests per 10 seconds per address and Cloudflare location. Verified crawlers are briefly blocked above the limit; other clients receive a managed challenge. Pages allow indexing.

This response header classifies traffic for the edge rules; it does not throttle origin requests. Independent installations need equivalent protection at their own edge. No live Cloudflare configuration was changed, and browser verification did not exercise its deployed challenge.

## Verification

The final `MIX_ENV=test MIX_TEST_PARTITION=atlas_review_20261002 ELIXIR_ERL_OPTIONS='+S 4' mix precommit --max-cases 2` passed compilation with warnings treated as errors, formatting, Credo, and all 2,515 tests (5 skipped, 1 excluded). A fresh isolated database removed leftover local fixture rows that had invalidated an earlier run.

Production-mode asset compilation passed for the dashboard and documentation bundles. Controller tests cover anonymous access, crawler classification, absence of session cookies, unpublished routes, representation negotiation, heading targets, social metadata, root routing, and protected application routes.

Headless Chrome verified GitHub links, the consolidated alert, complete Markdown clipboard contents, both themes, mobile navigation, unpublished routes, table scrolling, absence of horizontal overflow, and no script errors. Verification screenshots are hosted separately on GitHub and attached to the implementation pull request; they are not repository changes.


## Adversarial review

Claude reviewed the uncommitted implementation. It found no critical or high-severity defects in bootstrap safety, route isolation, or sanitization. The review fixes derive unique heading links from parsed Markdown, respect specific request preferences over wildcards, give missing pages a plain-text content type, canonicalize the overview address, and preserve the existing social image on rendering failures. Image capture has an absolute deadline and includes bounded failure output. Google provider options now have one configuration source and initialize at request time, including in compiled releases. The managed chart explicitly configures Tuist’s admission domain. Production compilation and a production-controller probe verified that the configured domain hint overrides a conflicting request hint. The chart passed `helm lint` and rendered successfully.

The existing Tuist admission default remains for compatibility. Production warns when Google credentials are configured without an explicit domain. A supported independent installation must configure its own domain; removing all Tuist defaults remains planned work. The bootstrap initialization audit event must never be pruned. Executive scopes synchronize through seeds and bootstrap, rather than at every startup. Social-image font reproducibility across hosts remains a follow-up; the committed image is served directly in production.
