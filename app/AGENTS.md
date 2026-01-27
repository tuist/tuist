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
- Build: `xcodebuild build -project TuistApp.xcodeproj -scheme TuistApp`
- Test: `xcodebuild test -project TuistApp.xcodeproj -scheme TuistApp`

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

## Environment Configuration
The app supports multiple environments via `TUIST_ENV`:
- `development` - Local server at localhost:8080
- `staging` - Staging server
- `canary` - Canary server
- Default - Production
