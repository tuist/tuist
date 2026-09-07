# Live (Web Layer)

This area owns LiveView pages and components for the web UI.

## Responsibilities
- Render LiveView pages and handle UI events.
- Orchestrate UI state while delegating domain operations to `server/lib/tuist`.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- Gradle task analytics live under Builds at `/builds/tasks` in `GradleBottlenecksLive`; per-build dependency exploration and timelines live in `GradleExecutionComponent`, mounted by `GradleBuildLive`. Omit the Tasks list heading and subtitle; retain the task name on detail pages. Task executions use the Gradle build runs Project cell (root project name and tags) and shared Ran by badge (CI, account name, or Unknown), retaining whole-row navigation to the execution detail. Task outcome badges use Succeeded (green), Failed (red), cache hits (blue), Up-to-date (purple), and skipped/no-source (neutral), consistently with the per-build tasks table. They follow the Test Case Runs table pattern: search, sorting, Branch filter, outcome/Ran by badges, duration, relative timestamps, and pagination. Task details show analytics and Task executions, with no Execution profile card. They have only Executions, Cache hit rate, and duration widgets; Executions is selected by default, and an inherited Tasks widget selection on detail falls back to Executions. Use the Builds-style Environment dropdown beside the date picker; limit table filters to Branch, applying the same cohort to analytics and history. Widget and metric selections replace the current browser history entry so Back returns to the preceding page. Use the shared Noora filter and sort menus in the task table toolbar, active filter chips, selectable widgets and chart for task analytics. The Cache hit rate widget charts a percentage from 0–100 with percentage-point trends (higher is better). Non-cacheable/unknown tasks show an explicit unavailable state without a numeric rate or trend. Legacy hits/misses widget URLs select hit rate. The duration widget defaults to p90 and switches between average and p50/p90/p99, using lowercase percentile labels. Keep cumulative task time in the table only. The duration chart includes the average and all three percentile series with a selectable legend, connects across unsampled intervals, and marks recorded samples (including genuine zero durations); duration increases are negative (red) and decreases positive (green); show “No change” when both values are zero, absolute changes when only the previous value is zero, and percentages otherwise; task duration columns use p50/p90/p99 like test cases. Show 0% for cacheable tasks without hits. When no hit rate is available, show Not cacheable or Unknown cacheability badges. Use Noora table cells for consistent column alignment and the Test Runs section spacing. Let the Noora table own horizontal scrolling so outer wrappers do not clip its border; keep dependency metrics in the per-build view. Dependency chain inspection belongs to a specific build, not a latest-build highlight on the aggregate Tasks page. Keep metrics in `Tuist.Gradle` and its subcontexts.

- Gradle build Cache Summary uses five widgets: Task hits, Task misses, Hit rate, Cache downloads, and Cache uploads. Keep remote-miss diagnostics in task-level inspection rather than additional summary cards.

- `GradleTaskExecutionLive` renders `/builds/build-runs/:build_run_id/tasks/:task_id`. Scope lookups to both the selected project and parent build. Build Tasks, cacheable tasks, and task-overview execution rows navigate here. The page links back to its build and to the task overview with root project, build path, task path, and type preserved. Use shared `Helpers.GradleTask` outcome labels and colors.

- Task execution details use one compact summary card (duration, runner, timestamp, cacheability, branch, shortened commit); show build identity, incremental status and available cache timings as further metadata rows. Display the root build path (`:`) as “Root build”. Omit raw execution reasons, caching-disabled explanations and dependency navigation. Reuse VCS branch/commit links.
