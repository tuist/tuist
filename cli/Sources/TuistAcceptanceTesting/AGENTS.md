# TuistAcceptanceTesting (CLI Module)

This module provides helpers used by CLI acceptance tests.

## Responsibilities
- Provide assertions over generated Xcode projects (framework linking, bundles, xcframework embedding).
- Use Swift Testing `Issue` recording to report assertion failures.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistTesting/AGENTS.md

## Invariants
- Assertions read `XcodeProj` files directly and inspect build phases.
