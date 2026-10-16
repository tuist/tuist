# Repository Instructions

- When posting comments or reviews on GitHub pull requests, do not use em dashes.
- Write GitHub pull request comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly asked to do so.
- For local reviews of Swift changes, use `../.blick/skills/tuist-swift-review/SKILL.md` as the project-specific review context.
- Use the shared `fileSystem` instance from `tuist/FileSystem` for filesystem operations. Convert URLs to `AbsolutePath` via the in-module `URL.absolutePath` helper. Do not use `Foundation.FileManager` in repository code, and do not call NIOFileSystem or `swift-tools-support-core` filesystem primitives directly.

## Authentication

- Keep registry provider selection separate from HTTP credential fallback. Match SwiftPM: registry chooses one provider, while HTTP composes environment, inline netrc, file netrc, and keychain providers. File netrc duplicates select the last match; inline duplicates select the first.
- Native resolution authentication is centralized in `NativeRegistryAuthentication`. Only check compatibility when the manifest graph, reachable registry pins, or source-control transformation indicate registry use; unused global settings must not block source-control-only packages. Warm no-fetch lockfile validation must bypass compatibility refusals. Legacy bridging accepts inline netrc only when enabled file credentials cannot conflict and the effective native registry configuration declares authentication types. Serialize unquoted tokens for Swift 6.0 compatibility; reject empty values, whitespace, comments (`#`), quotes, and NUL without exposing credentials. Never convert origin-scoped environment tokens into host-scoped netrc or rewrite user configuration/mirrors. Keep the credential owner's signal/cancellation cleanup and stdin-only secret transport covered by tests.
- Keychain reads must suppress approval dialogs in CI/headless sessions and distinguish missing items, access denial, policy infrastructure failure, and cancellation. Read in-process to preserve the embedding executable's item trust. Serialize SwifterPM's synchronous reads with `KeychainCredentialReader`; only headless reads temporarily disable legacy interaction and must restore the previous setting on success, failure, and cancellation. This flag is process-wide: other embedding code can observe it during the lookup. Interactive reads must not change it. Do not introduce an interpreter, credential subprocess/protocol, or LAContext-only suppression. Never log credentials. Cache only within a resolution, distinguish explicit ports, and cancel shared work when its last waiter leaves; an in-flight Security call itself cannot be interrupted. Denied registry access cannot fall back to file credentials; policy infrastructure failures permit anonymous registry requests. HTTP failures permit anonymous downloads. Route redacted warnings through `SwifterPM.withWarningHandler`, honor quiet, and never swallow cancellation.
- Git and submodules must use ambient Git credentials and the declared, mirror-applied transport. Do not inject provider API tokens into Git headers. Explicit `SWIFTERPM_GITHUB_TOKEN` and `SWIFTERPM_GITLAB_TOKEN` are only for provider API/archive optimizations.
- The generated `SwifterPMCoreTests` target covers authentication and HTTP helpers. Generate it with `tuist generate SwifterPMCore SwifterPMCoreTests --no-open`, then run `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing:SwifterPMCoreTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. The broader SwifterPM tests remain in the Bazel suite.

## Source restore

- Prefer provider archives, then shallow Git fetches. If Git reports that the server does not support shallow clients, retry the same location and pinned revision without `--depth`; do not retry unrelated fetch failures or switch transports.
- `RestoreTests` exercises this fallback offline using a loopback smart-HTTP Git fixture without the `shallow` capability.
- Unit tests calling `restorePackage` to evaluate fixture manifests must pass `disableSandbox: true`: Bazel's macOS test sandbox cannot launch a nested `sandbox-exec`. Keep the production sandbox default unchanged.

## End-to-end tests

- `mise run test:e2e` runs `e2e/resolution_spec.sh` and is part of CI. Scenarios that expect SwifterPM to do work itself (dump manifests, download registry archives) must first warm the cache with a resolve; a resolve without a lockfile or with uncached pins is delegated to native SwiftPM.
- Authenticated registry scenarios exercise Basic and Bearer credentials through cold, warm, lockfile-validation, missing-pin, and update paths. Their legacy Swift wrapper strips native environment providers and isolates `--security-path`; request records contain authorization outcomes, never secrets. Regression scenarios cover unused local/global/file registry settings, warm validation with exported credentials, public registry reads with the keychain enabled and interpreter execution forbidden, and restoration of headless keychain interaction policy on success/failure through injected unit tests. The scoped Swift wrapper isolates `--security-path` for all scenarios because HOME alone does not isolate macOS SwiftPM fingerprints.
- Read pins through `normalize_package_resolved_file`. SwiftPM writes the version 1 `Package.resolved` format for packages below tools version 5.6, which several SwiftPM fixtures are.
- Real-world graph scenarios require blank stderr as well as successful resolution and lockfile checks. Unexpected source-publication fallback is a cache regression, even when native resolution succeeds. Exercise intentional preservation/fallback separately in targeted tests.
- CI explicitly supplies `SWIFTERPM_E2E_GIT_TOKEN` to a Git credential helper scoped to HTTPS `github.com`. Pass its non-secret configuration through `GIT_CONFIG_COUNT` so fixture isolation can still disable host/global Git configuration. Never persist the token or use it as a production provider API token; local runs without the variable remain anonymous. `e2e/github_credential_spec.sh` checks credential scoping and Git integration.

## Source cache ownership

- Shared sources are pinned snapshots, not native working trees. `PinnedSourceSnapshot` exports through a private index and empty staging tree; never stamp and cache mutable checkout bytes. Empty/comment-only `.gitmodules` and files with no submodule path entries are valid; listing and filtering their configuration must not confuse Git's no-match status with a failed export. Malformed configuration still fails closed.
- Every native entry point must prepare a private workspace through `NativeWorkspace`, including force-resolved checks and Tuist's native fallback. Detach Git-bearing checkout links rather than copying potentially damaged working trees. Prefer APFS COW clones for Git-free links/artifacts, with independent-copy fallback; never use hard links. Account for per-file materialization and subsequent tree cleanup costs on large graphs; a matching revision marker alone cannot justify skipping isolation or certifying a mutated private copy.
- Recognize only explicit SwiftPM marker/manifest-cache paths as generated checkout metadata, including SwiftPM 6.4's `.build/CACHEDIR.TAG` and `.build/.buildSystem_debug`. Arbitrary files under `.build` remain user data.
- Preserve unmanaged/modified real checkouts and SwiftPM edit state. Legacy cached Git checkouts are rebuilt privately without modifying their shared directory; local source-control legacy entries retain private Git metadata/tags for manifest context. Cache publication failure must leave the usable native checkout intact.
- Keep source-cache paths and the raw revision marker compatible. Do not add warm source hashing or Git subprocesses for ordinary Git-free cache hits.
- `NativeWorkspaceTests`, `RestoreTests`, `ResolveTests`, and `FileSystemSupportTests` are also included in the generated `SwifterPMCoreTests` target for focused Xcode validation.

## Resolution

- Stale-pin pruning must only inspect version-specific cached sources or registry downloads. If a reachable manifest is missing or cannot be evaluated, retain the seed and defer to normal resolution. Never infer reachability from an unverified scratch checkout or a local repository working tree.

## CI

- CI runs the mise test tasks with `-- --config=ci`. The `ci` config in `.bazelrc` points Bazel's repository cache at the directory the workflow persists with `tuist/cache-volume` and widens Bazel's download retry window. Keep both paths in sync, and keep CI-only Bazel settings under `ci` so local runs are unaffected.
