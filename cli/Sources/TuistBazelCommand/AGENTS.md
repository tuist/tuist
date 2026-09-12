# Bazel commands

- `setup` configures remote caching, Remote Asset dependency downloads and build insights for ordinary Bazel commands. Use the cache endpoint and credentials for the remote downloader, explicitly enable local fallback for rolling Kura upgrades, and preserve custom/disabled downloader and fallback preferences when refreshing configuration. Origin credential propagation stays opt-in. A repository downloader preference must not block the managed import; insert the import before downloader preferences so their option precedence survives setup.
- `test` fetches every page of quarantined test cases before executing Bazel.
  Skipped cases exclude their entire target, including healthy cases. Muted
  cases run; only complete local reports proving every failure belongs to a
  muted case may turn Bazel's test-failure exit into success.
- Keep Bazel's own target expansion and test-suite expansion. Never translate
  generic case names into framework-specific test filters.
- Preserve Bazel failures and exit codes. A failed quarantine lookup must not
  silently execute a partial exclusion list.
- Missing skipped targets may be dropped only after a complete Bazel event log
  attributes a missing-target loading failure to them, before target configuration
  or execution. Retry the original selection, retain all other exclusions, and
  cap retries at five. Do not infer target existence from a differently configured query.
- `--no-quarantine` bypasses the lookup, exclusions, and failure suppression.
- Keep local event/report reads bounded and reject missing or malformed evidence.
- Keep report identities aligned with the server using the shared corpus in
  `cli/Tests/Fixtures/JUnitIdentity/AGENTS.md`. Namespace prefixes are ignored;
  ambiguous attributes with the same local name must fail closed.
- Warn when a failed case matches an older suite-based mute but now reports a
  different class identity. Do not transfer that policy automatically: multiple
  classes may have shared the old identity.
