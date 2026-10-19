# Home Dashboard

`HomeDashboard.kt` is the signed-in landing screen. Keep it section-based so new product surfaces can sit alongside recent previews without changing the full Previews browser.

Recent previews show at most three entries for the selected project, newest first, inside a Material card with a View All action. Use the compact shared preview row style (no commit hash or inline install action); keep the full row style in the Previews browser. Project selection lives in the top app bar, not inside the card. Reuse the project menu from `ui/previews`; the `PreviewsViewModel` is owned by `navigation/HomeScreen.kt`, not by the dashboard. Navigation callbacks open the full Previews tab or a preview detail with its project handle.

`HomeActivityCards.kt` adds independent build failures, failed test runs, and new flaky tests above previews, using the shell-owned `HomeActivityViewModel`. Each shows up to three records over seven days, links to existing browser details, and offers native sharing. New flaky means a current flaky-state transition during the window, not a recent run. Do not add CI controls or infer unresolved incidents from historical failures.

Project context is authoritative before preview loading finishes. Hide activity whose full handle does not match it immediately, preserve successful sibling sections and existing rows on refresh failures, suppress stale results/cancellation, and offer explicit per-section retry. Distinguish unavailable/old-server/unsupported sections from genuine empty successes; collapse identical all-section failures into one message without blocking previews. Pull-to-refresh updates both independent feeds.

Activity state tests live in `app/src/test/java/dev/tuist/app/ui/home/`; preview/context regressions remain in `app/src/test/java/dev/tuist/app/ui/previews/PreviewsViewModelTest.kt`. API mapping/link safety is covered under `data/home`.
