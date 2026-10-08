# Repository Instructions

- When posting comments or reviews on GitHub pull requests, do not use em dashes.
- Write GitHub pull request comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly asked to do so.
- For local reviews of Swift changes, use `../.blick/skills/tuist-swift-review/SKILL.md` as the project-specific review context.
- Use the shared `fileSystem` instance from `tuist/FileSystem` for filesystem operations. Convert URLs to `AbsolutePath` via the in-module `URL.absolutePath` helper. Do not use `Foundation.FileManager` in repository code, and do not call NIOFileSystem or `swift-tools-support-core` filesystem primitives directly.

## Authentication

- Keep registry provider selection separate from HTTP credential fallback. Match SwiftPM: registry chooses one provider, while HTTP composes environment, inline netrc, file netrc, and keychain providers. File netrc duplicates select the last match; inline duplicates select the first.
- Git and submodules must use ambient Git credentials and the declared, mirror-applied transport. Do not inject provider API tokens into Git headers. Explicit `SWIFTERPM_GITHUB_TOKEN` and `SWIFTERPM_GITLAB_TOKEN` are only for provider API/archive optimizations.
- The generated `SwifterPMCoreTests` target covers authentication and HTTP helpers. Generate it with `tuist generate SwifterPMCore SwifterPMCoreTests --no-open`, then run `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing:SwifterPMCoreTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. The broader SwifterPM tests remain in the Bazel suite.

## Resolution

- Stale-pin pruning must only inspect version-specific cached sources or registry downloads. If a reachable manifest is missing or cannot be evaluated, retain the seed and defer to normal resolution. Never infer reachability from an unverified scratch checkout or a local repository working tree.
