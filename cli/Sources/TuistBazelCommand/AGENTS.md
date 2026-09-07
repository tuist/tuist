# Bazel commands

- `setup` configures remote caching and build insights for ordinary Bazel commands.
- `test` fetches every page of quarantined test cases before executing Bazel.
  Skipped cases exclude their entire target, including healthy cases. Muted
  cases run; only complete local reports proving every failure belongs to a
  muted case may turn Bazel's test-failure exit into success.
- Keep Bazel's own target expansion and test-suite expansion. Never translate
  generic case names into framework-specific test filters.
- Preserve Bazel failures and exit codes. A failed quarantine lookup must not
  silently execute a partial exclusion list.
- `--no-quarantine` bypasses the lookup, exclusions, and failure suppression.
- Keep local event/report reads bounded and reject missing or malformed evidence.
