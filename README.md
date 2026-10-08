# Public project overview comparison

Before/after screenshots for the public-overview discovery change. These are publishing artifacts, not files included in the implementation pull request.

Captured with Chromium's headless shell at 1440 × 1100 with JavaScript disabled. The pages are actual server-rendered HTML from an isolated local test fixture (`public-overview-demo/tuist`, one five-second build), styled with the currently published dashboard stylesheet.

- Before: the previous public-page challenge plug redirects the anonymous root request to the challenge page. The external Turnstile widget is unavailable in the local fixture.
- After: the current root request renders the existing overview with its five-second average build time present in the initial HTML. JavaScript-driven charts and controls are deliberately not initialized.

No production configuration, feature flags or customer data were modified to produce these screenshots.
