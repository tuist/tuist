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
- `Sources/TuistAuthentication` - Shared authentication

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

## Environment Configuration
The app supports multiple environments via `TUIST_ENV`:
- `development` - Local server at localhost:8080
- `staging` - Staging server
- `canary` - Canary server
- Default - Production
