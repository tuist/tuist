# macOS Desktop

This directory contains the native macOS interface and the shared application lifetime. It lives in `TuistMenuBar` to reuse installation, device discovery, authentication, and progress services without exposing their internals across targets.

- `MacApplicationModel` owns one authentication service, device service, progress reporter, and Sparkle updater for the desktop and menu-bar companion. Register URL observation once, before any window is presented. OAuth callbacks must not be treated as preview installation links.
- `MacApplicationEnvironment` scopes app requests to a shared Keychain credentials store and in-process API cache. Do not accidentally use the CLI's filesystem credentials or cache defaults on macOS. Use it for structured desktop requests; `ErrorHandling.fireAndHandleError` applies it to user actions.
- `DesktopView` uses a native three-column `NavigationSplitView`: Home/Previews sidebar, project-scoped preview list, and preview details. Home uses a native GroupBox overview card with three recent previews and a View All action, rather than duplicating the full browser's List. It can grow additional sections when those features are available.
- The signed-in navigation shell owns a `TuistProjects.ProjectContext`, displayed above sidebar sections using `ProjectSwitcher`. Selection is scoped to the window; persisted selection/recents are scoped by server and account. Keep account/settings outside project scope.
- `DesktopPreviewsModel` consumes the project context and owns paginated preview data. Search filters loaded previews locally; loading another page expands the filter's results. Request identities and project checks prevent old project/page responses from replacing a newer selection. Switching projects clears preview detail selection while preserving the active sidebar section.
- `DesktopPreviewDetail` reuses `DeviceService` to install previews. Device selection and progress must remain shared with the menu-bar companion. The window's status bar shows installation progress even when no preview is selected, including installations started from a deep link or the menu bar.
- `DesktopSettingsView` uses the shared `showMenuBarExtra` preference. The main window remains available from the Dock and app menus even when the menu-bar companion is hidden.

Prefer standard SwiftUI macOS controls, system typography, keyboard navigation, selectable lists, contextual actions, and toolbars rather than mobile navigation or custom menu-row styling in desktop screens.

Tests belong in `app/Tests/TuistMenuBarTests/Desktop/` and use Swift Testing. Run the focused `TuistMenuBarTests/DesktopPreviewsModelTests` and `TuistMenuBarTests/DesktopProjectPickerTests` suites with the macOS `TuistApp` scheme. Picker tests render offscreen AppKit windows with mocked project discovery and storage, verifying native search, list sizing, and Return selection without launching the authenticated app or accessing credentials.
