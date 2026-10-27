# Tuist CLI (Swift)

## Boundaries
- The executable and runtime setup live in `Sources/tuist`. Add new commands and generation logic to feature-specific modules, not the legacy `TuistKit` and `TuistGenerator` monoliths.
- `ProjectDescription` is the public manifest DSL; `TuistLoader` evaluates it. `ProjectAutomation` is the serialized generated-project output, not the manifest DSL. Graph models are embedded under `Sources/XcodeGraph`.
- `TuistCacheEE` is a git submodule; keep its guidance inside the submodule.
- Preserve Noora logger setup for post-command completion/error output so verbose logs capture it.

## Build and test
Run from the repository root. Generate only the targets needed for the change:
```bash
tuist generate tuist ProjectDescription --no-open
xcodebuild build -workspace Tuist.xcworkspace -scheme tuist CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

If a production or test target is missing, regenerate with it explicitly rather than falling back to SwiftPM:
```bash
tuist generate tuist <ProductionTarget> <TestTarget> ProjectDescription --no-open
xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace \
    -only-testing <TestTarget>/<SuiteName> \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```
- `xcsiftbuild test` is also supported. Prefer suites or individual tests over whole targets; a single Swift Testing filter is `ModuleTests/SuiteName/function_name`.
- Do not use `swift build` or `swift test` for CLI validation. SwiftPM is allowed only when explicitly requested or when changing package-resolution behavior; always include `--replace-scm-with-registry` in those cases.
- Lint with `mise run cli:lint`; use `mise run cli:lint --fix` for automatic fixes.
- Every root `Package.swift` edit, including target-only changes and merge resolutions, changes `Package.resolved`'s `originHash`. Run `tuist install` and commit the refreshed lockfile; `cli.yml` checks it.
- Linux releases are static musl binaries. `mise run cli:bundle-linux --linux-vm --arch x86_64` uses the Swift container; `--arch x86_64|aarch64` (or `TUIST_LINUX_ARCH`) selects native/cross-compilation through the static SDK. Setup is shared with PR Linux builds in `mise/utilities/install_static_linux_sdk.sh`.
- Guard libc imports with `canImport(Darwin)`, `canImport(Glibc)`, and `canImport(Musl)`; Linux does not imply Glibc.

## Test conventions
- Use Swift Testing. For temporary directories, import `FileSystemTesting`, annotate with `@Test(.inTemporaryDirectory)`, and obtain the path with `try #require(FileSystem.temporaryTestDirectory)`.
- Test helpers must not mutate the global process environment.
- Avoid one-line comments unless they add useful context.
- Send user-facing warnings through `AlertController.current.warning(.alert("..."))` so completion collects them; reserve `Logger` for debug/trace output.

## Scoped contracts

- Read the relevant feature guide for [Bazel](Sources/TuistBazelCommand/AGENTS.md), [Cargo](Sources/TuistCargoCommand/AGENTS.md), [runner commands](Sources/TuistRunnerCommand/AGENTS.md), and [bundle analysis](Sources/Rosalind/AGENTS.md). Cargo and shared report identities have additional guides under `Tests/Fixtures/`.
- Coverage collection and evidence contracts live in [TuistXCResultService](Sources/TuistXCResultService/AGENTS.md); variant selection, warming, and export orchestration live in [TuistCache](Sources/TuistCache/AGENTS.md) and [TuistKit](Sources/TuistKit/AGENTS.md). TestCoverageAttribution is linked by test targets, never injected; per-target evidence comes from raw process profiles without it.
- Test/build-for-testing paths uploading coverage use `AtomicCoverageCounters`; settings must resolve to nothing without `CLANG_COVERAGE_MAPPING`, preserving noncoverage compiler arguments and cache keys.
- Tuist's own tests do not link TestCoverageAttribution: CI records target-only evidence, skipped tests carry only with their whole target, and remaining gaps stay gaps. Main runs use guarded `tuist coverage complete`; earlier-main backfills use `.github/workflows/tuist-project-coverage-backfill.yml` and main's tools.
- Coverage exports resolve products by name from build products or an app's `PlugIns`, and use `<executable>.debug.dylib` when the executable is a stub. Remote-mode runs publish the requested scheme before processor parsing. Preserve binary-cache instrumentation checks for actually linked slices and leave fetched-but-unused binaries unflagged.
- Bazel setup enables unmerged JSON trace profiles with target/primary-output identifiers and the remote BEP artifact uploader. Preserve explicit profiling preferences; do not enable `experimental_stream_log_file_uploads`.
- Bazel setup records active logical processors as `TUIST_CPU_COUNT` in machine-local `.bazelrc.tuist`. Refreshes preserve it, upgrades backfill it in existing insights/cache-only configurations, and setup must be rerun after CPU/location changes. JVM overrides must supply matching build metadata; job concurrency is not CPU capacity.
