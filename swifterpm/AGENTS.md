# Repository Instructions

- When posting comments or reviews on GitHub pull requests, do not use em dashes.
- Write GitHub pull request comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly asked to do so.
- For local reviews of Swift changes, use `../.blick/skills/tuist-swift-review/SKILL.md` as the project-specific review context.
- Use the shared `fileSystem` instance from `tuist/FileSystem` for filesystem operations. Convert URLs to `AbsolutePath` via the in-module `URL.absolutePath` helper. Do not use `Foundation.FileManager` in repository code, and do not call NIOFileSystem or `swift-tools-support-core` filesystem primitives directly.

## Authentication

- Keep registry provider selection separate from HTTP credential fallback. Match SwiftPM: registry chooses one provider, while HTTP composes environment, inline netrc, file netrc, and keychain providers. File netrc duplicates select the last match; inline duplicates select the first.
- Git and submodules must use ambient Git credentials and the declared, mirror-applied transport. Do not inject provider API tokens into Git headers. Explicit `SWIFTERPM_GITHUB_TOKEN` and `SWIFTERPM_GITLAB_TOKEN` are only for provider API/archive optimizations.
- The generated `SwifterPMCoreTests` target covers authentication and HTTP helpers. Generate it with `tuist generate SwifterPMCore SwifterPMCoreTests --no-open`, then run `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing:SwifterPMCoreTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. The broader SwifterPM tests remain in the Bazel suite.

## Source restore

- Prefer provider archives, then shallow Git fetches. If Git reports that the server does not support shallow clients, retry the same location and pinned revision without `--depth`; do not retry unrelated fetch failures or switch transports.
- `RestoreTests` exercises this fallback offline using a loopback smart-HTTP Git fixture without the `shallow` capability.

## End-to-end tests

- `mise run test:e2e` runs `e2e/resolution_spec.sh` and is part of CI. Scenarios that expect SwifterPM to do work itself (dump manifests, download registry archives) must first warm the cache with a resolve; a resolve without a lockfile or with uncached pins is delegated to native SwiftPM.
- Read pins through `normalize_package_resolved_file`. SwiftPM writes the version 1 `Package.resolved` format for packages below tools version 5.6, which several SwiftPM fixtures are.

## Resolution

- Stale-pin pruning must only inspect version-specific cached sources or registry downloads. If a reachable manifest is missing or cannot be evaluated, retain the seed and defer to normal resolution. Never infer reachability from an unverified scratch checkout or a local repository working tree.

## Manifest caches

- Validate dumps and package-info JSON by manifest contents (including version-specific candidates), the actual manifest environment and mirrors, toolchain identity, declared and resolved package paths, and sandbox mode. Checkout mtimes are not cache identities. Legacy or incomplete records must miss; never certify a legacy dump with current inputs.
- Bind cached output bytes to the input record, and capture inputs before evaluation. If inputs change during evaluation, do not publish a cache entry for that evaluation.
- All manifest dumps belong under the root scratch directory, outside materialized package roots. Local checkouts and registry roots can be replaced even when their sources are unchanged. Keep declared paths for evaluation and use canonical paths only for cycle detection and invalidation.
- `--report-timings` reports installation phase durations without changing the manifest environment. Preserve the native forced-lockfile check, and distinguish fresh-runner measurements from same-machine repeats.
- The generated `SwifterPMCoreTests` target includes manifest/cache, CLI and resolution coverage. Generate `SwifterPMCore SwifterPMCoreTests` and run the relevant suites through Xcode for focused validation.

## CI

- CI runs the mise test tasks with `-- --config=ci`. The `ci` config in `.bazelrc` points Bazel's repository cache at the directory the workflow persists with `tuist/cache-volume` and widens Bazel's download retry window. Keep both paths in sync, and keep CI-only Bazel settings under `ci` so local runs are unaffected.
