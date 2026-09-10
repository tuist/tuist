# Components (Web Layer)

This area owns shared UI components for LiveView and templates.

## Responsibilities
- Build timeline machine tracks form a responsive 2×2 grid above the step workspace. Each plot has its own ruler, cursor and focus region, synchronized to the same time range. The inspector and resize divider align with the top of the step chart section, including its controls, and share that section’s height. Step search and the legend sit directly above the step lanes, below machine metrics.
- Pass the build source to the shared timeline. Bazel uses a full-width CPU chart above memory and network; Xcode and Gradle retain the four-chart grid.
- Render source-specific legend labels: Bazel has File preparation, Fetching and Analysis/setup; Gradle has Testing, Packaging, Configuration and Artifact transforms. Their legend buttons expose the selected group via `aria-pressed`, with filtering handled locally by the hook. Xcode keeps its passive legend.
- Provide reusable UI components (navigation, auth components, forms).
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
