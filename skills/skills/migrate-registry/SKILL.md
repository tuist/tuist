---
name: migrate-spm-to-tuist-registry
description: Migrates Swift Package Manager dependencies to Tuist registry-compatible references in Xcode projects, Tuist generated projects, and Swift packages. Use when adopting the Tuist registry for an existing project.
---

# Migrate SPM Packages to Tuist Registry

## Project Types

| Project type | Where dependencies live | Validate with |
|---|---|---|
| Generated Tuist project with Xcode package integration | `Project.swift` `packages:` | `tuist generate --no-open` |
| Generated Tuist project with XcodeProj-based integration | `Tuist/Package.swift` `dependencies:` | `tuist install` |
| Generated Tuist project with `.external` integration | root `Package.swift` `dependencies:` | `tuist install` |
| Swift package | root `Package.swift` `dependencies:` | `swift package resolve` |
| Xcode project | Xcode package references | `xcodebuild -resolvePackageDependencies ...` |

Use the resolver that matches the project type. Migrate all package references first, then validate resolution.

## Quick Start

1. Detect the project type and where dependencies are declared.
2. If the project uses generated Tuist projects with `.remote` packages in `Project.swift`, enable `registryEnabled` in `Tuist.swift` and remove tracked generated `.xcworkspace` directories if the repo commits them.
3. Otherwise, migrate the relevant `Package.swift` or Xcode-managed package references directly.
4. Convert all eligible package references from URL-based declarations to registry-based ones.
5. Run the matching resolver command once after all package changes.
6. If resolution fails because a package is not available in the registry, revert that package and retry.

## Registry Setup

### Generated Tuist projects using `Project.swift` package references

If packages are referenced from `Project.swift`, enable the registry in `Tuist.swift`:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

`tuist generate` creates the registry configuration automatically. This setup is only needed for generated Tuist projects using package references in `Project.swift`.

### Swift packages and Xcode projects

Set up the registry manually:

```bash
tuist registry setup
```

Commit the generated registry configuration so the team and CI use the same setup.

## Detect the Project Type

- **Generated Tuist project with Xcode package integration**: packages are declared in `Project.swift`.
- **Generated Tuist project with XcodeProj-based integration**: packages are declared in `Tuist/Package.swift`.
- **Generated Tuist project with `.external` integration**: packages are declared in the root `Package.swift` and installed with Tuist.
- **Swift package**: the repository itself is a Swift package and uses `Package.swift` directly.
- **Xcode project**: package references are managed by Xcode in the project or workspace.

## Migration Syntax

### `Project.swift`

```swift
// Before
.remote(url: "https://github.com/pointfreeco/swift-composable-architecture", requirement: .upToNextMajor(from: "0.1.0"))

// After
.package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
```

### `Tuist/Package.swift` or `Package.swift`

```swift
// Before
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")

// After
.package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
```

### Xcode project

Xcode does not automatically replace source-control packages with registry packages. Remove the source-control package and add the registry package through Xcode's package dependency UI.

## Version Requirement Examples

### URL-based requirements in `Package.swift` or `Tuist/Package.swift`

```swift
.package(url: "https://github.com/apple/swift-log", from: "1.5.0")
.package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "9.9.0"))
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMinor(from: "1.18.1"))
.package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1")
.package(url: "https://github.com/example/package", "1.2.3"..<"1.2.6")
.package(url: "https://github.com/example/package", "1.2.3"..."1.2.6")
```

### URL-based requirements in `Project.swift`

```swift
.remote(url: "https://github.com/apple/swift-log", requirement: .upToNextMajor(from: "1.5.0"))
.remote(url: "https://github.com/pointfreeco/swift-snapshot-testing", requirement: .upToNextMinor(from: "1.18.1"))
.remote(url: "https://github.com/stencilproject/Stencil", requirement: .exact("0.15.1"))
.remote(url: "https://github.com/example/package", requirement: .branch("main"))
.remote(url: "https://github.com/example/package", requirement: .revision("abc123def456"))
```

### Registry-based equivalents

When you migrate to explicit registry references, keep the same semantic version rule where possible:

```swift
.package(id: "apple.swift-log", from: "1.5.0")
.package(id: "tuist.XcodeProj", .upToNextMajor(from: "9.9.0"))
.package(id: "pointfreeco.swift-snapshot-testing", .upToNextMinor(from: "1.18.1"))
.package(id: "stencilproject.Stencil", exact: "0.15.1")
.package(id: "example.package", "1.2.3"..<"1.2.6")
.package(id: "example.package", "1.2.3"..."1.2.6")
```

Branch and revision requirements are source-control specific. Keep them URL-based, or switch to a tagged version before migrating to explicit registry identifiers.

## Registry ID Format

- Format: `{owner}.{repo}`
- Use lowercase and replace `/` with `.`
- If the repository name contains `.`, replace it with `_`

Example:

```text
https://github.com/groue/GRDB.swift -> groue.GRDB_swift
```

## Migration Workflow

### Step 1 - Prepare the project

- Activate `mise` before running Tuist commands:

```bash
eval "$(mise activate bash)"
```

- If a generated Tuist project commits generated workspaces, remove stale `.xcworkspace` directories before validation.

### Step 2 - Convert all package references

- Update every eligible package declaration in the project type you detected.
- For generated Tuist projects with XcodeProj-based integration or `.external` integration, you can also keep URL declarations and rely on `--replace-scm-with-registry` when that better matches the project setup.
- For Xcode projects, replace packages in Xcode rather than editing generated artifacts by hand.

### Step 3 - Resolve dependencies once

Run the resolver that matches the project type:

```bash
# Generated Tuist project with Xcode package integration
tuist generate --no-open

# Generated Tuist project with XcodeProj-based or .external integration
tuist install

# Swift package
swift package resolve

# Xcode project
xcodebuild -resolvePackageDependencies
```

### Step 4 - Handle failures

- **`package not found on registry`**: revert that package to its original URL-based declaration and resolve again.
- **Resolver not found**: activate `mise` or use the project's existing toolchain setup first.
- **Mixed dependency styles**: keep package declarations in the single location used by that project type.

## Authentication

Authentication is optional.

- Unauthenticated: 1,000 requests per minute per IP
- Authenticated: 20,000 requests per minute per IP

```bash
tuist registry login
```

## Done Checklist

- The correct project type was identified before editing dependencies
- Registry setup matches the project type
- All eligible package references were migrated before validation
- Generated `.xcworkspace` directories were removed only when relevant
- The resolver command for the project type succeeds
- Packages missing from the registry remain URL-based
- Dotted repository names use `_` in the registry identifier
