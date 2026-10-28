# Embedded XcodeGraph

Graph models and mapping are embedded in the generated workspace.

## Scope
- `Sources/XcodeGraph` - Core graph models. Native package runtime roles preserve explicit dynamic-linkage hints separately from whether the product is embedded; existing enum representations remain unchanged.
- `Sources/XcodeMetadata` - Metadata extraction for precompiled artifacts.
- `Sources/XcodeGraphMapper` - Mapping from XcodeProj models into XcodeGraph models.
- `cli/Tests/XcodeGraphTests`, `cli/Tests/XcodeMetadataTests`, and `cli/Tests/XcodeGraphMapperTests` - Graph package tests in the root generated workspace. Native package mapping tests cover explicit dynamic hints, embedding roles, and unchanged legacy serialized values.

## Source Identity
- `SourceFile.contentHashIsPlaceholder` distinguishes script-generated declaration fingerprints from actual file-content checksums. Missing/nil preserves legacy decoding and normal-source encoding; keep existing initializer signatures and hashing inputs unchanged. Generated accessor checksums are not placeholders.

## Scheme Build Actions
- `BuildAction.buildFor` stores per-target purpose overrides: an absent key enables all five purposes, while an explicit empty set enables none.
- Mapping duplicate Xcode scheme build entries unions their purposes and retains one target reference in first-occurrence order.

## Commands
From the repository root:
- `tuist install` to restore dependencies.
- `tuist generate tuist XcodeGraphMapper XcodeGraphMapperTests ProjectDescription --no-open` to generate a focused workspace. Add the corresponding model or metadata test target when needed.
- `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing:XcodeGraphMapperTests/DynamicPackageDependencyMappingTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""` to run a focused mapping suite. Follow the root CLI guidance rather than falling back to SwiftPM builds or tests.
