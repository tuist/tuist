# Live (Web Layer)

This area owns LiveView pages and components for the web UI.

## Responsibilities
- Login and sign-up mount the shared `GoogleOneTap` hook; navigation cancels pending browser sign-in. Other authentication screens allow the required resources for later LiveView navigation but do not mount the chooser.
- Automation forms show the name followed by independently collapsible When (condition), What (actions), and Recovery sections with one-sentence summaries. Creation starts with When and What expanded and Recovery collapsed; editing starts with all three collapsed. Metric automation forms keep the one-time checkbox immediately above Create/Save to apply actions to existing matches, including Slack. Its description states that, unchecked, tests that currently match get no actions unless they recover and match again. Show a read-only asynchronous count of currently eligible matches; refresh it on modal opening and condition/state changes, cancel stale requests, and keep save available if counting fails. Reset the checkbox on every modal opening and reflect the choice in the submit label. Record the request in history, not as an ongoing condition; event-driven automations do not expose it.
- Xcode cache task rows asynchronously preload the first 20 CAS outputs for displayed expandable tasks after the LiveView connects. Successful empty loads remove the disclosure and close the row; failures retain expansion so they can be retried. Collapse retains loaded pages and pending requests for immediate re-expansion; filtering, sorting, task-page changes, tab changes, and build refresh cancel pending loads and clear loaded output pages. Load more appends the next batch while keeping existing outputs visible, prevents duplicate requests, and retries failed batches without skipping them. Expanded rows show loading and error states; failed preloads retry on expansion.
- Module cache miss widgets, charts, filters, and history share four reasons: Changed, Upstream, Cold, and Evicted. History rows show a reason badge and tooltip; classification and prior remote-hit evidence belong in Builds.Analytics. Test-only runs read Module Cache results from their original build event when their own event has no lookups; the fallback is project scoped and never changes reported counts.
- Xcode machine metrics with recorded build-relative offsets appear as shared-clock tracks in Timeline; legacy metrics without an offset retain the Machine Metrics tab. Samples travel in a small hook reply independently of the step metadata download.
- Render LiveView pages and handle UI events.
- The Xcode build detail loads only the selected tab's breakdown/cache queries. The Timeline hook downloads all step metadata from the authorized `timeline.json` HTTP endpoint (compressed by Bandit), while a small hook reply delivers machine metrics immediately. Step metadata never enters LiveView assigns or HTML. Keep metrics interactive above the step skeleton while metadata loads; abort downloads on navigation and reload on build completion. Keyboard navigation and step logs use cancellable async tasks scoped to the current build. Zoom, pan and search use the full metadata locally, with the full build duration initially visible. Older builds may have no timeline data.
- Orchestrate UI state while delegating domain operations to `server/lib/tuist`.
- Module-cache pages reuse their loaded breakdown for charts. Relative date presets stay fixed across table and widget patches; changing the date selection or remounting creates a new snapshot. Detail history filters refresh their relative window without reloading analytics or branch choices; cursor pagination retains the history window. Failed async loads retry on a matching patch while successful or in-flight loads are reused. Module count failure only affects its widget value; charts gate on their own series. Detail totals cover every product under the selected module name.
- Bazel exposes test case automations through the shared project settings tabs. Keep quarantine setup and target-level skipping guidance in the Bazel flaky-tests documentation, not page banners.
- Bazel's Skipped policy option explains whole-target exclusion, including healthy tests, at the manual and automation action menus. Keep this guidance scoped to Bazel.
- Xcode overview charts opt into Noora's `data-lazy="true"` behavior so charts
  below the viewport do not initialize while the visible analytics are loading.

- Code coverage has three pages. `CoverageLive` (`/tests/coverage`) is a glance at the **default branch** over the chosen period — analytics, recent commits, coverage gaps — with "Other branches" in the header and a "View more" on each card leading to the default branch's own page. `CoverageBranchesLive` (`/tests/coverage/branches`) lists every branch that gathered coverage, searchable, each carrying the pull request it was pushed for; a branch with one leads to the pull request, the rest to `/tests/coverage/branches/*branch`. `CoverageDetailLive` renders a branch, a pull request or a commit through one template with Overview, Commits (not for a commit), Targets and Files tabs; every figure describes the subject's head commit against its baseline, and a branch also carries its distance from the default branch. Shared cells and labels live in `TuistWeb.Coverage.Components`. A file's per-line detail is deliberately API- and MCP-only.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- Gradle task analytics live under Builds at `/builds/tasks` in `GradleTasksLive`. Omit the Tasks list heading and subtitle; retain the task name on detail pages. Task executions use the Gradle build runs Project cell (root project name and tags) and shared Ran by badge (CI, account name, or Unknown), retaining whole-row navigation to the execution detail. Task outcome badges use Succeeded (green), Failed (red), cache hits (blue), Up-to-date (purple), and skipped/no-source (neutral), consistently with the per-build tasks table. They follow the Test Case Runs table pattern: search, sorting, Branch filter, outcome/Ran by badges, duration, relative timestamps, and pagination. Task details show analytics and Task executions, with no Execution profile card. They have only Executions, Cache hit rate, and duration widgets; Executions is selected by default, and an inherited Tasks widget selection on detail falls back to Executions. Use the Builds-style Environment dropdown beside the date picker; limit table filters to Branch, applying the same cohort to analytics and history. Widget and metric selections replace the current browser history entry so Back returns to the preceding page. Use the shared Noora filter and sort menus in the task table toolbar, active filter chips, selectable widgets and chart for task analytics. The Cache hit rate widget charts a percentage from 0–100 with percentage-point trends (higher is better). Non-cacheable/unknown tasks show an explicit unavailable state without a numeric rate or trend. Legacy hits/misses widget URLs select hit rate. The duration widget defaults to p90 and switches between average and p50/p90/p99, using lowercase percentile labels. Keep cumulative task time in the table only. The duration chart includes the average and all three percentile series with a selectable legend, connects across unsampled intervals, and marks recorded samples (including genuine zero durations); duration increases are negative (red) and decreases positive (green); show “No change” when both values are zero, absolute changes when only the previous value is zero, and percentages otherwise; task duration columns use p50/p90/p99 like test cases. Show 0% for cacheable tasks without hits. When no hit rate is available, show Not cacheable or Unknown cacheability badges. Use Noora table cells for consistent column alignment and the Test Runs section spacing. Let the Noora table own horizontal scrolling so outer wrappers do not clip its border. Keep metrics in `Tuist.Gradle` and its subcontexts.

- Gradle build Cache Summary uses five widgets: Task hits, Task misses, Hit rate, Cache downloads, and Cache uploads. Keep remote-miss diagnostics in task-level inspection rather than additional summary cards.

- `GradleTaskExecutionLive` renders `/builds/build-runs/:build_run_id/tasks/:task_id`. Scope lookups to both the selected project and parent build. Build Tasks, cacheable tasks, and task-overview execution rows navigate here. The page links back to its build and to the task overview with root project, build path, task path, and type preserved. Use shared `Helpers.GradleTask` outcome labels and colors.

- Task execution details use one compact summary card (duration, runner, timestamp, cacheability, branch, shortened commit); show build identity and incremental status as further metadata rows. Display the root build path (`:`) as “Root build”. Omit raw execution reasons, caching-disabled explanations and dependency navigation. Use a single Cache badge for Not cacheable or the observed cache result (hit, local hit, miss, error), falling back to Cacheable or Unknown cacheability when no result is available; omit a separate Remote lookup field. Reuse VCS branch/commit links.

- GitLab CI connections in Integrations take only an instance URL and runner token. GitLab and Buildkite cards share `runner_integrations_visible?`, derived from the account runners feature flag. Disconnect replaces Connect in the card header after connecting; show the instance URL only in its editable field. Each job selects an account-owned profile through its pipeline tags. Never repopulate token inputs; job detail views load account-scoped metadata without execution payloads.

- GitLab disconnect disables the connection immediately and leaves upstream settlement to background polling; the disabled connection renders a pending notice and a disabled Disconnect action.

- Runner job detail omits the whole Insights card unless at least one build or test run matches the runner job; candidate account projects alone do not justify an empty card. GitLab jobs link to their GitLab instance and omit the structured Steps card, which currently receives data only from GitHub completion webhooks; GitLab execution output remains available in Logs.

- Runner job Overview links to mounted cache volumes in a Volumes table, showing that job's cache outcome and recorded sizes. Omit the card when no mounts are recorded. Scope reads to account, workflow run and job; show the latest mount per volume and preserve unknown measurements.

- `BuildTimelineLoader` owns lazy metric bootstrapping, build identity, versioning, tab reentry and forced refresh for Xcode, Gradle and Bazel. It cancels superseded bootstrap tasks and rejects stale/inactive-tab hook requests. Step metadata stays out of LiveView state: every source supplies an authorized HTTP URL to `build_timeline_section`, which shares loading/error UI. Xcode keeps cancellable server navigation/log tasks; Gradle and Bazel navigate downloaded steps locally, with Bazel logs loaded separately when available.

- Gradle and Bazel detail tabs follow Xcode: Overview, Timeline, then cache and source-specific tabs. Gradle machine metrics appear only in Timeline; legacy `tab=machine-metrics` links open Timeline without eagerly loading samples on other tabs.

- Humanize display counts with `format_number/2` (10,000+ uses K/M/B/T), including table cells and dropdown values. Keep chart series, sort keys, filters, and pagination inputs numeric.

- GitLab edit forms submit the connection identifier as `_id` and remap it to the context’s `id`; never use `name="id"` on an input because it shadows the form DOM property used by LiveView.

- Automation match previews use one stable async key and a 500ms condition-change debounce. Keep condition validation consistent across the summary, preview, and save path, including required event selections for event-driven monitors; an unchecked explicit save cancels pending existing-match actions.

- Only expose Timeline when the selected build has recorded steps or aligned machine samples. Shared `BuildTimelineLoader.select_tab/3` falls back to Overview for unavailable direct links; Xcode processing refreshes recheck availability. Bazel requires a published profile; retained summary spans alone do not qualify. Availability checks use scoped existence/scalar queries, never full step downloads.

- `RunnerVolumesLive` shows account-scoped Linux cache usage and job history.
  Account storage totals ignore search/pagination and show measurement coverage.
  Use Jobs-style Noora cards, widgets, search and navigable rows. Volume detail
  shows Volume details above the Overview and Jobs tabs on both views.
  Overview shows Analytics and Recent jobs. Recent jobs includes the five
  most recent jobs with a View more link to Jobs. Load full paginated job history
  only on Jobs. Inventory and job history pagination follow Jobs with Prev/Next
  buttons, chevrons, and disabled controls at page boundaries. Job tables show one
  Mounted at timestamp from the successful mount, rather than a separate finish time. Size history is not exposed as a tab; old links fall back to
  Overview. Keep measurements for storage charts.
  Unknown measurements stay unknown. Logical retained bytes are not physical
  storage or billing. Delete confirmations recheck account-update access;
  invalidate generations immediately and show physical cleanup as pending until
  agents acknowledge it. See `Tuist.Runners.CacheVolumes` for lifecycle rules.

- The volume inventory uses three equal-width selectable widgets (Volumes, Used space and Cache hit rate), period-end storage trends, and the shared Noora line chart. Default to Used space. Use the shared date picker in the Storage header (24 hours, 7 days, 30 days, custom within 90 days); persist ranges across search and pagination. Historical widget values and chart bounds follow the selected range. Compare the period endpoint with the previous period endpoint; unavailable comparisons use the Jobs zero fallback (the shared badge displays “No change”). Volume counts deduplicate concurrent copies and use count formatting; sizes use byte formatting. Keep the chart free of headings, period labels and explanatory banners; measurement coverage belongs in widget tooltips. Omit the inventory Status column. Empty volumes without a saved head show zero used bytes; preserve unknown measurements for saved volumes and pending deletion. Volume details show Repository, Platform, Last used and Capacity; omit Status, Last reported and Average attach.

- Volume detail analytics reuse the inventory date picker and selectable charts for used bytes, hit rate and job runs. Capacity belongs in Volume details, not a selectable analytics widget. Scope all series to the volume and chosen range; mounts determine activity timestamps. Preserve the range between tabs. Show percentage charts from 0–100 and count charts as bars; absent hit-rate observations remain unknown. Do not display an eviction banner. Last used reflects a successful mount, not allocation or agent heartbeats.

- Volume charts follow Jobs with short date labels on the x axis; retain the hour in tooltips rather than appending midnight to date ticks.

- Volume inventory uses 20-row server pagination. The Jobs-style Sort by menu and sortable headers cover volume, repository, used space, capacity and last used. Sort changes reset the page and preserve search/date range; page links retain sorting. Default to most recently used.

- Keep the inventory Sort by control beside search with Jobs toolbar spacing. Include the Jobs-style Linux platform badge; macOS remains a separate follow-up. Capacity without a report reads "Not reported", not a guessed zero or default disk size; confirmed reclaimed storage still reads zero.

- Volume clearing uses “Clear volume” in the trigger, modal title and confirm action, with a short header description. Cache update policy is not user-configurable; omit its controls and metadata. Label mount activity “Job runs”.

- Volume job rows use job names when available (ID fallback), a Workflow column (Unknown fallback), and Jobs-style status badges. Label the lifecycle column Cache status and successful publication Saved to distinguish it from the job outcome. Explain every cache lifecycle status in a shared Noora tooltip available on hover and keyboard focus.

- Inventory Cache hit rate aggregates known mount outcomes across the account for the selected range, independently of table search and pagination. Weight by mounts, not per-volume rates; exclude unknown outcomes and retain missing buckets as gaps. Show a 0–100% chart with an unavailable state when no outcomes exist. Capacity stays in tables and volume details. Hit-rate trends compare weighted rates with the preceding equal-length period in percentage points, with increases positive. Exclude the current start boundary from the previous period. Show No previous data or No data when comparison inputs are missing.
