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

- Bundling the macOS app shells out to `create-dmg`, which styles the DMG window by driving Finder from AppleScript. macOS gates that behind a `kTCCServiceAppleEvents` approval for Finder, seeded into the runner image in `infra/runner-image/runner.pkr.hcl` and present from `runner-image@0.13.3`. On an image without it the send waits on an authorization prompt no headless VM can answer and gives up with `Finder got an error: AppleEvent timed out. (-1712)`; retrying only multiplies the wait.
- The macOS and iOS jobs allow 50 minutes because `tuist generate` runs with `--no-binary-cache`, making each release a full archive whenever the compilation cache is cold. Any runner image roll leaves it cold, so the first release after one runs far longer than a warm release.

## Environment Configuration
The app supports multiple environments via `TUIST_ENV`:
- `development` - Local server at localhost:8080
- `staging` - Staging server
- `canary` - Canary server
- Default - Production
