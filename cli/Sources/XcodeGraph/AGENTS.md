# Embedded XcodeGraph Package

This directory embeds `tuist/XcodeGraph` into this repository as a local Swift package dependency.

## Scope
- `Sources/XcodeGraph` - Core graph models. Native package runtime roles preserve explicit dynamic-linkage hints separately from whether the product is embedded; existing enum representations remain unchanged.
- `Sources/XcodeMetadata` - Metadata extraction for precompiled artifacts.
- `Sources/XcodeGraphMapper` - Mapping from XcodeProj models into XcodeGraph models.
- `cli/Tests/XcodeGraphTests`, `cli/Tests/XcodeMetadataTests`, and `cli/Tests/XcodeGraphMapperTests` - Graph package tests in the root generated workspace. Native package mapping tests cover explicit dynamic hints, embedding roles, and unchanged legacy serialized values.

## Integration
- The root package manifest references this package with `.package(path: "cli/Sources/XcodeGraph")`.
- Product names exposed to the main package are:
  - `XcodeGraph`
  - `XcodeMetadata`
  - `XcodeGraphMapper`

## Commands
From the repository root:
- `tuist install` to restore dependencies.
- `tuist generate tuist XcodeGraphMapper XcodeGraphMapperTests ProjectDescription --no-open` to generate a focused workspace. Add the corresponding model or metadata test target when needed.
- `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing:XcodeGraphMapperTests/DynamicPackageDependencyMappingTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` to run a focused mapping suite. Follow the root CLI guidance rather than falling back to SwiftPM builds or tests.
