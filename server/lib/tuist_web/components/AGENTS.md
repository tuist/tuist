# Components (Web Layer)

This area owns shared UI components for LiveView and templates.

## Responsibilities
- `LayoutComponents.head_canonical_link` shares canonical URLs across marketing, docs, and app layouts. Project descriptions fall back to page and project identity; preserve explicit descriptions and keep social URL metadata aligned with the canonical URL.
- `LayoutComponents.head_analytics_scripts` loads Glossia independently with `async` on hosted production marketing, documentation and dashboard pages. Use `https://glossia.ai/assets/glossia-web.js` with the `tuist.dev` domain and keep the `https://glossia.ai` script and collection origin aligned with the shared content security policy, and honor `analytics_disabled?` for embedded visualizations.
- `GoogleOneTap` shares the protected credential form and configuration gates between marketing pages and login/sign-up LiveViews. It supports static mounting and LiveView lifecycle hooks.
- Widget legends and breakdown dots support amber for aggregate cache misses (All), distinct from individual miss-category colors using the existing amber chart token.
- Build timeline machine tracks form a responsive 2×2 grid above the step workspace. Each plot has its own ruler, cursor and focus region, synchronized to the same time range. The inspector and resize divider align with the top of the step chart section, including its controls, and share that section’s height. Step search and the legend sit directly above the step lanes, below machine metrics. The step skeleton and download failure state must leave already-loaded metrics visible.
- A Mix timeline (`source="mix"`) has its own legend groups: Compilation, Type checking, Writing to disk, Other compilers, Other and Failed. They reuse the lane colours of the closest groups of the other build systems (`setup`, `resource`, `script`). Its inspector hides Project and labels the target as File, because a Mix build's unit of work is the file.
- Pass the build source to the shared timeline. Bazel uses a full-width CPU chart above memory and network; Xcode and Gradle retain the four-chart grid.
- Render source-specific legend labels: Bazel has File preparation, Fetching and Analysis/setup; Gradle has Testing, Packaging, Configuration and Artifact transforms. Their legend buttons expose the selected group via `aria-pressed`, with filtering handled locally by the hook. Xcode keeps its passive legend.
- Provide reusable UI components (navigation, auth components, forms).
- Bazel projects use the shared Flaky Tests and Quarantined Tests navigation alongside their test runs and cases.
- `BuildTimeline` uses Noora cards, search and empty states around the Xcode build timeline hook, without embedding step payloads in HTML, with translated controls and accessible step details in a resizable right-hand inspector shown only when a step is selected, including its recorded log loaded on demand. Project and target are separate fields; type and outcome use Noora badges, and duration uses the standard history icon.
- Keep rendering logic here; avoid domain logic.
- `Runs.ProjectWithTags` shares project/scheme cells and tag overflow rules across build and task tables; detail headings reuse its uncollapsed tags.
- Widgets and trend badges accept an optional formatted trend value for absolute changes when a percentage is undefined. Zero trends default to “No change”; percentage rendering remains shared across pages.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- `recorded_build_timeline` wraps Gradle/Bazel loading and coverage states around the same `BuildTimeline` component. Non-Xcode inspectors display recorded operation categories and task outcomes, including cache hits, skipped work and unknown outcomes; they hide logs when no per-step logs are recorded.

- Run cache details and JSON comparisons use individual recorded hash inputs. Missing historical destinations and other unrecorded inputs display as unavailable; recorded empty inputs remain distinguishable. Test device and runtime rows appear only in selective-testing details.

- Expanded cache targets list sorted direct target dependencies, linking to module details within the selected project, and retain the aggregate dependencies hash separately. JSON comparisons include both names and the hash.

- `build_timeline_section` shares the initial loading/error states for all build systems. Every timeline supplies an HTTP metadata URL; machine metrics bootstrap independently through the shared LiveView loader.

- Widgets and legends format numeric values through `CldrHelpers.format_number/2`; preformatted strings retain their units. Count table cells must use the same helper.

- Do not render fallback coverage or internal clock-origin banners. Pages hide Timeline when the required recorded data is unavailable; Bazel requires a published profile, not retained build-summary spans. Preserve coverage and clock-origin metadata in the API.

- `AsyncCard` coordinates required analytics results through a readiness flag while preserving each card’s existing loading markup. Guard required result reads with that flag, keep optional results independently guarded, and leave header actions available. Use `async_section` around analytics inside a card with synchronous table content. Failed required loads render the shared error section; successful content stays mounted during refresh. Scatter charts retain points during refresh and show an explicit failure within the chart area. Their requested period can update before the points finish refreshing, so keep the pending state visible.


- Existing build tables show shared failure categories for Gradle, Xcode, Bazel and Once. Build Runs pages sort and filter this virtual column in the database before pagination; successful, cancelled and unfinished runs leave it empty. `BuildHealth` uses Noora neutral light-fill badge cells for recorded failure categories and plain dashes for non-failures; focusable Noora tooltips explain the classification, and shares category labels/filter options and the Gradle estimated task time saved widget and chart. Preserve missing versus zero estimates and source-specific navigation. Gradle detail fields use the same responsive metadata grid and duration icon.

- Widgets may provide `value_caption` for short visible context beneath their values; it defaults to absent. Gradle task time estimates use “Cumulative task time” in the widget and build details, with the full elapsed-time distinction retained in the tooltip.
