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
2. Configure the registry for that project type.
3. Convert all eligible package references from URL-based declarations to registry-based ones.
4. Remove tracked generated `.xcworkspace` directories only when working in a generated Tuist project that commits them.
5. Run the matching resolver command once after all package changes.
6. If resolution fails because a package is not available in the registry, revert that package and retry.

## Registry Setup

### Generated Tuist projects

Enable the registry in `Tuist.swift`:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

`tuist generate` creates the registry configuration automatically.

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
.package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")

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
