# Embedded XcodeGraph Package

This directory embeds `tuist/XcodeGraph` into this repository as a local Swift package dependency.

## Scope
- `Sources/XcodeGraph` - Core graph models.
- `Sources/XcodeMetadata` - Metadata extraction for precompiled artifacts.
- `Sources/XcodeGraphMapper` - Mapping from XcodeProj models into XcodeGraph models.
- `Tests/` - Upstream tests copied with the package.

## Integration
- The root package manifest references this package with `.package(path: "cli/Sources/XcodeGraph")`.
- Product names exposed to the main package are:
  - `XcodeGraph`
  - `XcodeMetadata`
  - `XcodeGraphMapper`

## Commands
From the repository root:
- `swift package resolve --replace-scm-with-registry`
- `swift build --replace-scm-with-registry`
- `tuist install`
