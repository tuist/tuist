# Tuist App (iOS and macOS)

This node covers the Tuist companion app under `app/`. The app provides a menu bar interface for macOS and an iOS app for managing Tuist projects and previews.

## Project Structure
- `Sources/TuistApp` - Main app target (macOS and iOS)
- `Sources/TuistMenuBar` - macOS menu bar functionality
- `Sources/TuistPreviews` - iOS preview management
- `Sources/TuistOnboarding` - iOS onboarding flow
- `Sources/TuistProfile` - iOS user profile
- `Sources/TuistNoora` - iOS design system components
- `Sources/TuistErrorHandling` - Shared error handling
- `Sources/TuistAppStorage` - Shared storage utilities
- `Sources/TuistAuthentication` - Shared authentication and persisted server selection

## Building and Testing
- Generate the project: `tuist generate --no-open` (from `app/` directory)
- Build: `xcodebuild build -workspace TuistApp.xcworkspace -scheme TuistApp`
- Test: `xcodebuild test -workspace TuistApp.xcworkspace -scheme TuistApp`

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
Both login screens open on Tuist-hosted sign-in, with a "Self-hosted server" option below the sign-in buttons that asks for an HTTPS server URL. Once a server is saved, the screen shows its address (tap to edit) and offers "Use Tuist-hosted" to clear it. The selected URL and OAuth client ID are persisted together in `AppServerConfigurationKey`, and signing in copies that server into the persisted `AuthenticationState.loggedIn(account:server:)`, so a session always knows which server it belongs to. While signed in, `AppServerEnvironmentService` resolves the server from the session; the selection only applies while signed out. Use `AppServerEnvironmentService` for all app API requests and credential cleanup, not the CLI's `ServerEnvironmentService` directly. Choosing "Use Tuist-hosted" clears the custom selection; signing out retains it for the next login.

Saving a self-hosted URL reads `registration_endpoint` from `/.well-known/oauth-authorization-server` and registers the app as a public PKCE client (RFC 7591) with the `tuist://oauth-callback` redirect, so no client ID is hardcoded or advertised per deployment. The registration endpoint must be on the selected server's origin. Servers without dynamic registration show an update error instead of attempting login with the hosted client ID. Custom URLs require HTTPS with a certificate trusted by the device; do not bypass TLS verification or add broad App Transport Security exceptions.

OAuth credentials retain their issuing client ID through storage and refresh in `TuistServer`. Keep this metadata when rotating tokens so an on-premise session never refreshes with the hosted client ID.

## Environment Configuration
The app supports multiple environments via `TUIST_ENV`:
- `development` - Local server at localhost:8080
- `staging` - Staging server
- `canary` - Canary server
- Default - Production
