# Tuist App (iOS and macOS)

This node covers the Tuist companion app under `app/`. The app provides a native desktop application with an optional menu-bar companion on macOS, and an iOS app for managing Tuist projects and previews.

## Project Structure
- `Sources/TuistApp` - Main app target (macOS and iOS). The iOS `HomeView` is the extensible, section-based landing page, initially showing recent previews.
- `Sources/TuistMenuBar` - Shared macOS services and the menu-bar quick launcher.
- `Sources/TuistMenuBar/Desktop` - Native macOS Home/Previews window, preview details, login, Settings, and shared application state; see `Sources/TuistMenuBar/Desktop/AGENTS.md`. The app uses a regular Dock presence and native SwiftUI welcome and authenticated main `Window` scenes, tabbed `Settings`, and an optional `MenuBarExtra` (off by default). Logged-out users only see the iOS-inspired welcome window; main-window restoration and implicit Window-menu entry points are disabled. Closing a window keeps the app running; Dock reopen and Open Tuist (⌘0) route to welcome or main according to authentication.
- `Sources/TuistPreviews` - iOS preview management and reusable preview UI/state for Home. Home is the default tab and presents a compact overview card with the three newest previews and a View All action; Previews retains the full paginated browser. Keep the compact Home row style distinct from the full browser; do not add placeholder widgets for unavailable product areas. Both tabs consume the shell's `ProjectContext` and share one `PreviewsViewModel` for preview data. Project selection appears in both navigation bars as a native quick-switch menu with an explicit Switch Project action for the full-height searchable picker; changing projects resets project-specific navigation but preserves the selected tab. Preview destinations capture their project handle. The signed-in root waits for initial project discovery before routing a typed preview destination, selecting its project when available. Public preview links remain readable even if their project is absent from the account's project list; the destination always carries its own project handle.
- `Sources/TuistProjects` - Shared project context and native project switcher for both platforms; see `Sources/TuistProjects/AGENTS.md`. Preferences and recent projects are scoped by server and account, independently of feature models.
- `Tests/TuistPreviewsTests` - iOS project context, preview, and Home state tests (the `TuistPreviews` scheme)
- `Sources/TuistOnboarding` - iOS onboarding flow
- `Sources/TuistProfile` - iOS user profile, including the connected server address and optional deployment version. Both iOS Profile and macOS Account settings use `AppServerInfoService` for lazy, nonblocking metadata discovery; see `../server/server-info.md`. Preserve normal operation on servers without the endpoint and keep app/server versions distinct.
- `Sources/TuistNoora` - iOS design system components
- `Sources/TuistErrorHandling` - Shared error handling
- `Sources/TuistAppStorage` - Shared storage utilities
- `Sources/TuistAuthentication` - Shared authentication, system web-authentication session lifetime, and persisted server selection; see `Sources/TuistAuthentication/AGENTS.md`.

## Building and Testing
- Generate the project: `tuist generate --no-open` (from `app/` directory)
- Build: `xcodebuild build -workspace TuistApp.xcworkspace -scheme TuistApp`
- Test: `xcodebuild test -workspace TuistApp.xcworkspace -scheme TuistApp`
- For an interactive iOS Simulator build that can sign in, keep Xcode's simulator signing enabled: `CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-"`. Xcode embeds the simulated Keychain entitlements during linking. Signing-disabled compile checks do not provide those entitlements, and manually attaching device entitlements with `codesign` is not equivalent.
- `TuistMenuBarTests` are unhosted macOS logic tests. Keep them independent of the `TuistApp` executable so running service/model tests does not launch the desktop UI, read a developer's session, or start device discovery.
- iOS preview tests: use the `TuistPreviews` scheme with an iOS Simulator destination; sources live in `Tests/TuistPreviewsTests`.

## Dependencies
The app depends on several CLI modules:
- `TuistServer` - Server API client
- `TuistSupport` - Shared utilities
- `TuistCore` - Core domain models
- `TuistHTTP` - HTTP client
- `TuistLogging` - Shared logging, including persistent Apple application logs and support exports
- `TuistAutomation` - Automation utilities
- `TuistSimulator` - Simulator management

## Code Style
- Follow Swift conventions used in the CLI.
- Use SwiftUI for new UI components.
- Do not add one-line comments unless truly useful.

## Releasing
`.github/workflows/app-release.yml` runs on pushes to `main` that touch `app/**`, `mise/tasks/app/**`, or the `cli/Sources/*` modules the app links. Changes to the workflow itself, or to the runner image the release runs on, do not trigger it, so a fix to either one stays unproven until an app path changes.

- Bundling the macOS app builds the DMG with `dmgbuild`, which writes the window layout into the image's `.DS_Store`. Layout lives in `app/dmg-settings.py`. Nothing in the release drives Finder, and it must stay that way: the fleet's VMs have no Finder that answers, so the previous tool, `create-dmg`, waited out a 120 second AppleEvent timeout on every attempt and no release could produce a DMG. That is an unreachable Finder rather than an unapproved one, so seeding TCC does not help; the approval seeded in `infra/runner-image/runner.pkr.hcl` was an attempt at this and did not fix it.
- The macOS and iOS jobs allow 50 minutes because `tuist generate` runs with `--no-binary-cache`, making each release a full archive whenever the compilation cache is cold. Any runner image roll leaves it cold, so the first release after one runs far longer than a warm release.
- `CFBundleVersion` is epoch seconds. It must exceed the newest `sparkle:version` in `app/appcast.xml`, or `generate_appcast` files the build as an old update: it writes no appcast entry and moves the DMG into `old_updates`, which is how `app@0.25.5` published with no DMG and pointed the Homebrew cask at a 404. It ran on `github.run_number` twice before, and both times the counter reset below the high-water mark when the workflow was recreated.
- `generate_appcast` mutates the directory it reads, so it runs against a copy in `app/build/appcast-input` rather than the artifacts directory the release uploads from.

## Branding Assets
- `Resources/TuistApp/AppIcon.icon` is an Icon Composer bundle (layers in `Assets/`, composition in `icon.json`). It needs Xcode 26 or later to compile; `xcode-select` pointing at an older Xcode fails on the asset catalog. Every layer must carry an explicit `"glass"` value: Icon Composer omits the key at its default (`true`), so a re-exported layer without it renders as Liquid Glass, and faint textures such as the grid turn into bright ridges at Dock and Finder sizes while looking fine at 1024px. Preview at ~95pt, not at full size.
- `Resources/TuistApp/Assets.xcassets/TuistIcon` (macOS sign-in view) and `TuistRoundedIcon` (iOS sign-in and launch screen) are flat renders derived from the compiled `AppIcon.icon`; regenerate them when the icon changes. `MenuBarIcon` (status item) and `TuistLogo` (iOS sign-in button) are the monochrome mark rasterised at 16pt and 20pt.
- `assets/dmg-background.tiff` is a HiDPI TIFF (660x400 at 1x plus 1320x800 at 2x, built with `tiffutil -cathidpicheck`). Keep it light and fully opaque: Finder draws the icon labels black in both light and dark appearance whenever a picture background is set, and dmgbuild has no label colour setting. The icon coordinates in `app/dmg-settings.py` are tied to the arrow drawn in the image.

## Self-Hosted Login
Both login screens always show the same Tuist-hosted sign-in buttons, with a "Self-hosted server" option below them that asks for an HTTPS server URL and goes straight to that server's login page. Closing that page returns to the same screen. The Tuist-hosted buttons clear any saved selection before signing in; a saved self-hosted URL only prefills the address prompt. The selected URL and OAuth client ID are persisted together in `AppServerConfigurationKey`, and signing in copies that server into the persisted `AuthenticationState.loggedIn(account:server:)`, so a session always knows which server it belongs to. While signed in, `AppServerEnvironmentService` resolves the server from the session; the selection only applies while signed out. Use `AppServerEnvironmentService` for all app API requests and credential cleanup, not the CLI's `ServerEnvironmentService` directly. Signing out retains the selection, so the address prompt is prefilled next time.

Saving a self-hosted URL reads `registration_endpoint` from `/.well-known/oauth-authorization-server` and registers the app as a public PKCE client (RFC 7591) with the `tuist://oauth-callback` redirect, so no client ID is hardcoded or advertised per deployment. The registration endpoint must be on the selected server's origin. Servers without dynamic registration show an update error instead of attempting login with the hosted client ID. Custom URLs require HTTPS with a certificate trusted by the device; do not bypass TLS verification or add broad App Transport Security exceptions.

OAuth credentials retain their issuing client ID through storage and refresh in `TuistServer`. Keep this metadata when rotating tokens so an on-premise session never refreshes with the hosted client ID.

## Preview Browsing
The macOS menu lists previews across all branches and all result pages. Do not use the `latest` API specifier for discovery: it restricts results to the project's default branch. Launching a tile must match its bundle identifier, not simply use the project's newest build. Search distinct compatible apps first; only fall back to full history for older servers that apply supported-platform filtering after distinct selection. Reject repeated or empty nonterminal pages instead of silently capping the search.

The shared `ServerPreview` preserves optional tracks and release notes, including compatibility with older responses that omit either field. iOS uses native search across display names and full release notes and horizontally scrolling Tracks pills in the full Previews browser, with shared project selection in the navigation toolbar. Home's three recent previews remain unfiltered when browser search or track selection changes; refreshing either surface updates the unfiltered overview without clearing browser filters. The selected pill is purple; All resets the filter without a separate Clear button, menu, or alert. Load complete project-scoped names and counts from the authorized `/previews/tracks` summary, never from a downloaded preview page. Counts are full-project totals, stable across search and track filters; All includes untracked previews. Search runs server-side before pagination, combines with the selected track, and resets on project changes. Debounce input and suppress cancelled or superseded results/errors. Keep browsing available on older servers without discovery, without inventing partial track choices or counts. Filter by whole track name on the server before pagination, reset track and choices when changing projects (including project-list refresh fallback), and ignore both results and errors from superseded list and track-discovery requests. Track storage is case-insensitive (`citext`), so unsupported-filter detection must accept case-only differences while rejecting missing or genuinely different tracks. Release notes are plain text, not Markdown or HTML. Show only the first nonblank line in preview list rows, truncated to one line, and keep full notes on preview detail pages. Never interpret snippets as Markdown or HTML. Keep the track tag beside the commit hash. Empty states use native pull-to-refresh, not a redundant Refresh button. Filtered empty results explain how to adjust search or track selection; unfiltered empty states explain pulling down. Await the refresh operation so the native indicator follows the request, and refresh projects when no projects are loaded.

## Environment Configuration
The app supports multiple environments via `TUIST_ENV`:
- `development` - Local server at localhost:8080
- `staging` - Staging server
- `canary` - Canary server
- Default - Production
