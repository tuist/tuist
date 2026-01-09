# AGENTS.md

This file is the root Intent Node for the Tuist repository. It provides high-level guidance and points to deeper context in subdirectories. Follow downlinks for the area you are changing.

## Repository Map
- `cli/` - Tuist CLI (Swift)
- `server/` - Tuist Server (Elixir/Phoenix)
- `cache/` - Tuist cache service (Elixir/Phoenix)
- `app/` - Tuist iOS and macOS app
- `handbook/` - Company handbook (VitePress)
- `docs/` - Documentation and guides
- `infra/` - Infrastructure and deployment assets

## Git and Pull Requests
Use conventional commit scopes:
- `app` - Tuist iOS and macOS app
- `server` - Tuist server (Elixir/Phoenix)
- `cache` - Tuist cache service (Elixir/Phoenix)
- `cli` - Tuist CLI (Swift)
- `docs` - Documentation
- `handbook` - Handbook/guides

Examples:
- `feat(server): add new telemetry sanitizer module`
- `fix(cli): resolve cache artifact upload issue`
- `feat(cache): add new S3 transfer worker`
- `docs(handbook): update project setup guide`

## Global Guardrails
- Do not modify `CHANGELOG.md` (auto-generated).
- Do not edit translation `.po` files; only the `tuistit` bot should change them.
- Do not modify content in languages other than English (source language).

## Intent Layer Maintenance
When making changes in a directory with an `AGENTS.md`, keep that node up to date. If a new subsystem or boundary is introduced, add a new leaf `AGENTS.md` and link it from the nearest parent node.

## CLI Workflow
- The Xcode project is generated with Tuist running `tuist generate --no-open`.
- When compiling Swift changes, use `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace` instead of `swift build`.
- When testing Swift changes, use `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing MyTests/SuiteTests` instead of `swift test`.
- Prefer running test suites or individual test cases (not the whole test target) for performance.

## Related Context (Downlinks)
- Tuist CLI: `cli/AGENTS.md`
- Tuist Server: `server/AGENTS.md`
- Tuist Cache service: `cache/AGENTS.md`
- Tuist Handbook: `handbook/AGENTS.md`

For deeper subsystem context, follow the downlinks inside each of the files above.
