# Shared Project Context

`ProjectContext` owns project discovery, selection, search, and recent projects, independently of any feature. The signed-in navigation shell creates one context per window/session and passes it to feature models. Scope persisted preferences by both server URL and account handle; never use another account's selection as the initial project. The old unscoped preference is intentionally not migrated, so the first upgrade resets selection once rather than guessing which account/server owned it.

`ProjectSwitcher` is navigation chrome: an iOS toolbar menu showing the current project name and a chevron, offering up to five unique quick choices (selected project first, then recents and available projects) plus an explicit Switch Project action opening a full-height searchable sheet, or a macOS sidebar-header button opening a searchable popover. Keep the iOS label visible rather than collapsing it to an unlabeled icon. Keep account/profile/settings outside project scope. Switching projects preserves the active section but clears project-specific navigation and hides data belonging to the previous project immediately.

The context captures the credentials/cache task-local stores at initialization and reapplies them to project requests, including requests initiated by the picker. Construct macOS contexts inside `MacApplicationEnvironment.withValue` so picker tasks cannot fall back to CLI filesystem credentials.

Tests live in `app/Tests/TuistPreviewsTests/ProjectContextTests.swift` and run with the iOS `TuistPreviews` scheme. Use Swift Testing, injected services, and isolated storage; do not modify process environment variables.
