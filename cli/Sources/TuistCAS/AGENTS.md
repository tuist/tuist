# TuistCAS (CLI Module)

This module resolves cache URLs for the CLI and the compilation-cache proxy, and records local Xcode cache setup configuration.
The Xcode compilation-cache transport lives in `cas-plugin/`.

## Responsibilities
- Derive hosted cache URLs locally from the account handle: `<account>.cache.tuist.dev`, with `-staging` or `-canary` appended to the account in those environments.
- Honor optional `TUIST_CACHE_ENDPOINT` first, bypassing discovery.
- Recognize the exact hosted server URLs and derive their stable hostname without any discovery request. Other servers use `GET /api/cache/endpoint`, which returns one main URL; do not choose between addresses or probe latency. Validate handles before composing DNS names.
- Cache self-hosted endpoint configuration in process for the response max-age (at most 60 seconds); never record demand or poll provisioning during URL resolution. Actual cache requests wake archived hosted instances through the shared activation gateway; authentication and provisioning are server responsibilities.

- `XcodeCacheInstallationStore` uses injected `FileSysteming`, asynchronous persistence/metadata operations, and `AbsolutePath` for filesystem paths. Its `cas-install.json` records only the setup Tuist version, LaunchAgent/program modification times, Xcode build version, and whether a plugin was installed. Invalidate it before setup or teardown changes; record it only after successful setup. Trust its version only while both modification times still match. Read the actual executable and Xcode directory from the LaunchAgent, without copying its credentials. Generation remains read-only and version-based, not a binary comparison or runtime health check. Suppress upgrade warnings for a verified newer setup, but still report Xcode changes or missing files. A retained plugin without an agent or manifest stays silent after teardown.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md

- Empty discovered configurations use local storage with a warning in ordinary builds and proxy startup; malformed endpoints and authentication errors remain errors. Never fall back from self-hosted discovery to a managed hostname. Hosted accounts using private/custom nodes require the explicit override.
- `tuist cache config` returns a project-scoped exchanged cache token so the Xcode proxy carries signed placement origin. The server is upgraded ahead of the CLI; exchange failures propagate, including 404, without returning raw credentials.
