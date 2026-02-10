---
name: migrating-to-tuist-generated-projects
description: Migrates existing Xcode projects to Tuist generated workspaces with build and run validation, external dependency mapping, and migration checklists. Use when adopting Tuist for an existing app or converting a hand-edited Xcode project to generated projects.
---

# Migrating to Tuist Generated Projects

## Quick Start

1. Baseline build and run the app with xcodebuild.
2. Inventory targets, build settings, and external dependencies.
3. Create `Tuist.swift`, `Project.swift`, and `Tuist/Package.swift`.
4. Extract settings into `.xcconfig` files and wire them in `Project.swift`.
5. Generate and build: `tuist generate --no-open` then `xcodebuild build`.
6. Fix build issues, regenerate, and validate runtime on a simulator.

## Preflight Checklist

- Primary app scheme and any extension/test schemes
- Targets list (app, extensions, tests, helper tools)
- Deployment targets and bundle identifiers
- Info.plist locations and entitlements
- Custom build settings (per target and per configuration)
- External dependencies (SPM, XCFrameworks, local packages)
- Build scripts (SwiftGen, Sourcery, codegen)
- Runtime validation plan (simulator destination and launch command)

## Outputs

- `Project.swift` and `Tuist.swift`
- `Tuist/Package.swift` for external dependencies
- `.xcconfig` files (optional but recommended)
- Build and runtime validation notes
- A short migration log of decisions and fixes

## Migration Workflow

### 1. Baseline the project

Start by proving the current project builds and runs. Capture the command you use so the generated workspace can be validated the same way.

```bash
xcodebuild build \
  -project App.xcodeproj \
  -scheme App \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath DerivedDataBaseline
```

### 2. Map targets and settings

List every target and its role. Extract build settings into `.xcconfig` files when they are large or shared across targets. Keep deployment targets and bundle identifiers identical to the original project to avoid runtime surprises.

### 3. Add Tuist manifests

Create the manifests and keep them minimal and close to the existing project.

- `Tuist.swift`: enable generation options you need and keep them explicit.
- `Project.swift`: define targets, sources, resources, scripts, and dependencies.
- `Tuist/Package.swift`: list external dependencies and map product types.

Use `.external` for third-party dependencies to keep the graph consistent.

### 4. Handle sources and resources carefully

Be precise here. Small mistakes often cause large failures later.

- `.intentdefinition` files belong in `sources`, not `resources`.
- `.xcstrings` should remain the primary localization source. Avoid double-including `.strings` or `.stringsdict` from overlapping globs.
- Use `.folderReference` for bundles like `Settings.bundle`.
- If a resource bundle is missing, ensure the package target declares `.process("Resources")`.

### 5. Generate and build

```bash
tuist install
tuist generate --no-open
xcodebuild build \
  -workspace App.xcworkspace \
  -scheme App \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath DerivedDataTuist
```

### 6. Resolve build issues iteratively

Common fixes you will likely need:

- **Missing SDK frameworks**: add `.sdk(name: ..., type: .framework)`.
- **SPM resource bundles**: verify `.process("Resources")` and `Bundle.module` usage.
- **File-system-synchronized groups**: avoid over-excluding directories; compare with the pbx if a type vanishes.
- **Invalid bundle identifiers**: override with `PackageSettings` or vendor a local package.
- **Generated sources**: ensure codegen outputs (SwiftGen/Sourcery) are part of the build.

### 7. Validate runtime

A build is not enough; launch the app on a simulator.

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted DerivedDataTuist/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch booted com.example.app
```

## Common Failure Patterns

- **Type not found**: a source file or entire directory was excluded accidentally.
- **Copy Bundle Resources errors**: Swift files are being treated as resources; fix the resource globs.
- **Localization conflicts**: `.xcstrings` colliding with `.strings` globs.
- **Undefined symbols**: missing SDK frameworks or dependency products.
- **Unrecognized selector at launch**: ObjC categories in static frameworks were stripped. Add `-ObjC` to `OTHER_LDFLAGS` or `-force_load` for the library that defines the category.
- **Runtime crash on launch**: mismatched bundle id, missing entitlements, or miswired resources.

## Migration Notes to Capture

- What changed in `Project.swift` and why
- Any exclusions or overrides (and the reason)
- Dependency patches or local vendoring
- The exact build and run commands used for validation

## Done Checklist

- Generated workspace builds cleanly
- App launches on simulator without immediate crash
- All targets and extensions build
- Dependencies are wired through `.external`
- Settings match the original Xcode project
