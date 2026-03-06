---
name: migrate-spm-to-tuist-registry
description: Migrates Swift Package Manager dependencies in Project.swift or Tuist/Package.swift from URL-based declarations to Tuist registry-based package references, validating generation after each change. Use when adopting the Tuist registry for an existing project.
---

# Migrate SPM Packages to Tuist Registry

## Syntax by File

| File | URL-based | Registry-based |
|------|-----------|----------------|
| `Project.swift` | `.remote(url: "https://...", requirement: ...)` | `.package(id: "owner.repo", from: "x.y.z")` |
| `Tuist/Package.swift` | `.package(url: "https://...", from: "x.y.z")` | `.package(id: "owner.repo", from: "x.y.z")` |

`Project.swift` uses `.remote(url:)`. `Tuist/Package.swift` uses `.package(url:)`.

## Quick Start

1. Detect which integration style the project uses.
2. Remove checked-in `.xcworkspace` directories before migration.
3. Enable registry in `Tuist.swift` with `registryEnabled: true`.
4. Follow the migration path for the detected integration style.
5. Run `tuist generate --no-open` after each replacement.
6. Keep the registry ID on success; revert on failure.
7. Commit the final state with only the successfully migrated packages.

## Preflight Checklist

- Detect integration style
- Remove any existing `.xcworkspace` directories tracked in the repo before changing package declarations
- Confirm `Tuist.swift` exists (not `Config.swift`)
- Note exact version requirements for each package
- Ensure `mise` is activated once per session before running `tuist`

## Detect Integration Style

Determine where packages are declared:

**Project.swift-based** — packages live in the `packages:` array of each `Project.swift`:
```swift
// Projects/App/Project.swift
let project = Project(
    packages: [
        .remote(url: "https://github.com/firebase/firebase-ios-sdk", requirement: ...)
    ]
)
```

**XcodeProj-based (Tuist/Package.swift)** — packages live in `Tuist/Package.swift` as a Swift package manifest:
```swift
// Tuist/Package.swift
let package = Package(
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "11.8.1")
    ]
)
```

A project should use one style only. If `Tuist/Package.swift` has a non-empty `dependencies` array, it is XcodeProj-based. If `Project.swift` files have non-empty `packages:` arrays, it is Project.swift-based.

## Registry ID Format

Tuist registry uses Swift Package Index as its backend, so a package must exist there to migrate.

- Format: `{owner}.{repo}` — all lowercase, dots instead of slashes
- Example: `https://github.com/firebase/firebase-ios-sdk` → `firebase.firebase-ios-sdk`

If the repository name contains `.`, replace it with `_`.

```
https://github.com/groue/GRDB.swift → groue.GRDB_swift
```

## Outputs

- `Tuist.swift` updated with `registryEnabled: true`
- Eligible dependencies migrated to registry-compatible declarations
- Packages not on the registry left in their original URL-based form

## Migration Workflow

### Step 1 — Remove existing workspaces

Delete checked-in `.xcworkspace` directories first so Tuist regenerates them from the updated dependency graph.

```bash
rm -rf *.xcworkspace
```

Remove nested workspaces too, if present.

### Step 2 — Enable the registry (both styles)

Add `registryEnabled: true` to `generationOptions` in `Tuist.swift`. Do not create a separate `Config.swift`.

```swift
let tuist = Tuist(
    fullHandle: "org/repo",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            registryEnabled: true
        )
    )
)
```

`tuist generate` creates the registry configuration automatically.

### Step 3 — Activate mise (once per session)

```bash
eval "$(mise activate bash)"
```

### Step 4A — Project.swift-based migration

Replace one `.remote(url:)` entry at a time:

```swift
// Before
.remote(url: "https://github.com/firebase/firebase-ios-sdk",
        requirement: .upToNextMajor(from: "11.8.1"))

// After
.package(id: "firebase.firebase-ios-sdk", from: "11.8.1")
```

Use `from:` directly, not `requirement: .upToNextMajor(from:)`.

After each change, run `tuist generate --no-open`:
- **Success** → keep, move to the next package
- **`package not found on registry`** → revert to `.remote(url:)`, move to the next package

Repeat for every entry across all `Project.swift` files.

### Step 4B — XcodeProj-based migration (`Tuist/Package.swift`)

Use one of these options:

**Option A — explicit `id:` references**: guarantees registry-first resolution.
```swift
// Tuist/Package.swift — replace one at a time and validate after each
.package(id: "firebase.firebase-ios-sdk", from: "11.8.1")
```

**Option B — `--replace-scm-with-registry`**: keeps URL declarations and resolves from the registry when available.
```swift
let tuist = Tuist(
    fullHandle: "org/repo",
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"]
        )
    )
)
```

`--replace-scm-with-registry` only applies to XcodeProj-based integration. It does not affect `Project.swift` packages.

## Authentication

Without authentication, the registry allows **1,000 requests per minute per IP**. For teams or CI, log in to raise the limit to **20,000 requests per minute**:

```bash
tuist registry login
```

This requires a Tuist account and `fullHandle` in `Tuist.swift`. Commit the generated registry configuration so CI and teammates share the same setup.

## Important Constraints

- Keep packages in one place only: either `Project.swift` or `Tuist/Package.swift`
- `packages:` in `Project.swift` and dependencies in `Tuist/Package.swift` conflict at generation time
- Remove stale `.xcworkspace` directories before the first `tuist generate --no-open`
- Do not run `tuist registry setup` manually; `registryEnabled: true` handles it

## Common Failure Patterns

- **`no registry configured for '...' scope`**: `registryEnabled: true` is missing from `Tuist.swift`
- **`package not found on registry`**: the package is not on Swift Package Index; revert to the original URL-based declaration
- **Wrong ID for dotted repo names**: `groue/GRDB.swift` must be `groue.GRDB_swift`, not `groue.GRDB.swift`
- **`tuist: command not found`**: run `eval "$(mise activate bash)"` first
- **Generation fails after mixing locations**: packages defined in both `Project.swift` and `Tuist/Package.swift`; pick one and remove the other

## Done Checklist

- `registryEnabled: true` is set in `Tuist.swift`
- Existing `.xcworkspace` directories were removed before regeneration
- Every package has been tried for registry migration
- Successful migrations use registry-compatible package declarations
- Packages not on the registry remain URL-based
- Dotted repo names use `_` instead of `.` in the ID
- `tuist generate --no-open` succeeds cleanly
