# Home Dashboard

`HomeDashboard.kt` is the signed-in landing screen. Keep it section-based so new product surfaces can sit alongside recent previews without changing the full Previews browser.

Recent previews show at most five entries for the selected project, newest first. Reuse the shared preview rows and project picker from `ui/previews`; the `PreviewsViewModel` is owned by `navigation/HomeScreen.kt`, not by the dashboard. Navigation callbacks open the full Previews tab or a preview detail with its project handle.

Keep loading, empty, failure/retry, and pull-to-refresh states available as sections are added. State tests live in `app/src/test/java/dev/tuist/app/ui/previews/PreviewsViewModelTest.kt`.
