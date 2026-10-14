# TuistCAS (CLI Module)

This module resolves cache URLs for the CLI and the compilation-cache proxy, and records local Xcode cache setup configuration.
The Xcode compilation-cache transport lives in `cas-plugin/`.

## Responsibilities
- Derive hosted cache URLs locally from the account handle: `<account>.cache.tuist.dev`, with `-staging` or `-canary` appended to the account in those environments.
- Honor optional `TUIST_CACHE_ENDPOINT` first, bypassing discovery.
- Recognize the exact hosted server URLs and derive their stable hostname without any discovery request. Other servers use `GET /api/cache/endpoint`, which returns one main URL; do not choose between addresses or probe latency. Validate handles before composing DNS names.
- Cache self-hosted endpoint configuration in process for the response max-age (at most 60 seconds); never record demand or poll provisioning during URL resolution. Actual cache requests wake archived hosted instances through the shared activation gateway; authentication and provisioning are server responsibilities.

- `XcodeCacheInstallationStore` records the setup Tuist version, launching executable, Xcode directory/build version, and installed component paths in `cas-install.json` beside the plugin, only after successful setup. Invalidate it before changing setup and after successful teardown. Its generation-time check is read-only and version-based, not a binary comparison: the launcher CLI also affects cache behavior. Trust the record only while the LaunchAgent modification time, resolved executable and its modification time, and configured Xcode directory still match. Otherwise report an unknown legacy/changed setup and use the LaunchAgent's actual Xcode directory. Do not copy LaunchAgent credentials into metadata. Suppress upgrade warnings for a verified newer setup, but still report Xcode changes or missing files. A retained plugin without an agent or manifest is silent after teardown. Metadata is not evidence of running-process health or which plugin image Xcode has loaded.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistCache/AGENTS.md
- cas-plugin/AGENTS.md

- Empty discovered configurations use local storage with a warning in ordinary builds and proxy startup; malformed endpoints and authentication errors remain errors. Never fall back from self-hosted discovery to a managed hostname. Hosted accounts using private/custom nodes require the explicit override.
- `tuist cache config` returns a project-scoped exchanged cache token so the Xcode proxy carries signed placement origin. The server is upgraded ahead of the CLI; exchange failures propagate, including 404, without returning raw credentials.
