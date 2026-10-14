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

## End-to-end tests

- `mise run test:e2e` runs `e2e/resolution_spec.sh` and is part of CI. Scenarios that expect SwifterPM to do work itself (dump manifests, download registry archives) must first warm the cache with a resolve; a resolve without a lockfile or with uncached pins is delegated to native SwiftPM.
- Authenticated registry scenarios exercise Basic and Bearer credentials through cold, warm, lockfile-validation, missing-pin, and update paths. Their legacy Swift wrapper strips native environment providers and isolates `--security-path`; request records contain authorization outcomes, never secrets. Regression scenarios cover unused local/global/file registry settings, warm validation with exported credentials, public registry reads with the keychain enabled and interpreter execution forbidden, and restoration of headless keychain interaction policy on success/failure through injected unit tests. The scoped Swift wrapper isolates `--security-path` for all scenarios because HOME alone does not isolate macOS SwiftPM fingerprints.
- Read pins through `normalize_package_resolved_file`. SwiftPM writes the version 1 `Package.resolved` format for packages below tools version 5.6, which several SwiftPM fixtures are.

## Resolution

- Stale-pin pruning must only inspect version-specific cached sources or registry downloads. If a reachable manifest is missing or cannot be evaluated, retain the seed and defer to normal resolution. Never infer reachability from an unverified scratch checkout or a local repository working tree.

## CI

- CI runs the mise test tasks with `-- --config=ci`. The `ci` config in `.bazelrc` points Bazel's repository cache at the directory the workflow persists with `tuist/cache-volume` and widens Bazel's download retry window. Keep both paths in sync, and keep CI-only Bazel settings under `ci` so local runs are unaffected.
