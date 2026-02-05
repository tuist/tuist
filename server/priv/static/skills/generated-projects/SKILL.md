---
name: using-tuist-generated-projects
description: Guides day-to-day work in Tuist-generated Xcode workspaces: generation, build and test commands, and buildable folders. Use when working in a Tuist-generated project or when users mention `tuist generate`, `tuist test`, or generated workspaces.
---

# Using Tuist Generated Projects

## Quick Start

```bash
# Generate workspace without opening Xcode
tuist generate --no-open

# Build a scheme with xcodebuild
xcodebuild build -workspace App.xcworkspace -scheme App

# Run tests with Tuist (supports selective testing)
tuist test App
```

## Project definition

### Prefer buildable folders

Use `buildableFolders` instead of `sources` and `resources` globs. Buildable folders stay synchronized with the file system, so adding or removing files does not require regeneration.

```swift
let target = Target(
  name: "App",
  buildableFolders: [
    "App/Sources",
    "App/Resources",
  ]
)
```

### Tag targets for focus

Use target tags to group areas of the project, for example:

- `tag:team:*`
- `tag:feature:*`
- `tag:layer:*`

These tags make it easier to scope generation and testing later.

### Align build configurations

Keep build configurations aligned between the project and external dependencies. Use `PackageSettings(settings: .settings(configurations: []))` to mirror project configurations; mismatches emit warnings.

## Workflows

### Generate intentionally

- Use `tuist generate --no-open` in automation and scripts to avoid launching Xcode.
- Regenerate when any manifest changes (or the dependency graph changes).
- If generation fails due to missing products, run `tuist install` to resolve dependencies and retry.

### Scope work with tags and targets

If someone is focusing on a specific area of the project, ask which area they mean and map that to either:
- A target tag (preferred), or
- A concrete list of targets.

You can obtain targets and their relationships using:

```bash
tuist graph --format json
```

The graph can be large, so filter it before sharing or processing it.

When working on a focused area, generate only what you need:

```bash
tuist generate tag:feature:payments
tuist generate PaymentsUI PaymentsTests
```

### Build with xcodebuild

Use `xcodebuild build` against the generated workspace and scheme.

```bash
xcodebuild build \
  -workspace App.xcworkspace \
  -scheme App \
  -destination "generic/platform=iOS Simulator"
```

### Test with tuist test

Use `tuist test` for generated projects. It hashes the project and can skip test targets whose hashes were already recorded by previous runs (local or CI).

```bash
tuist test App
# UI tests require a destination
tuist test --device "iPhone 14 Pro"
# Force all tests when you need full coverage
tuist test --no-selective-testing
```

## Guidelines

- Keep `buildableFolders` paths aligned to the target's real file system layout.
- Avoid overlapping `buildableFolders` with `sources` or `resources` globs in the same target.
- Open Xcode manually when needed after running `tuist generate --no-open`.

## Troubleshooting

**Static side effects warnings:** adjust product types deliberately. Use `Target.product` for local targets and `PackageSettings(productTypes:)` for external products. Making everything dynamic with `.framework` can compile and run, but it may hurt launch time. Prefer static products (static frameworks or libraries) when possible and when they do not introduce side effects.

**Objective-C dependency crashes:** add `-ObjC` or `-force_load` via `OTHER_LDFLAGS` on consuming targets as needed. Reference: `https://docs.tuist.dev/en/guides/features/projects/dependencies#objectivec-dependencies`.
