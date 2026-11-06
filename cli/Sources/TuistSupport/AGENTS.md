# TuistSupport

Keep shared utilities dependency-light; do not depend on feature modules.
`ProjectPathProviding` exposes parsed command paths to config and analytics
without duplicating environment-variable mappings.

## Invariants
- Logger configuration honors environment variables (quiet, osLog, detailed, verbose).
- `FatalError` types are used to classify user-facing failures vs. unexpected errors.
- Caller-owned cache-warm scratch directories are created when absent and must be empty when present.
- Direct native SwiftPM resolve/update calls, including `TUIST_USE_SWIFTERPM=0`, must run through SwifterPM's private-workspace preparation using the actual package/scratch/build-path arguments; native must not mutate shared source/artifact aliases.
- Program-status reports are disabled by default outside the CLI entry point and suppressed for non-interactive stdout, CI, machine-readable output, and quiet mode. Messages are single-line, control-free UTF-8, base64-encoded, and bounded to the protocol's 2048-byte decoded limit.
- Status output is best-effort: write errors, including a revoked terminal, must not change command results or exit status.
- Handled cancellation reports `idle`. Tuist intentionally does not install signal handlers for status reporting: Ctrl-C retains its existing process-group and termination semantics, and relies on terminal-side cleanup at process exit or the next shell prompt.

- On GitHub Actions, automatic package-manifest filtering hides provider prefixes and SSH agent paths while retaining the provider marker, runner OS/architecture, toolchain settings and application inputs. Keep manifest evaluation/fingerprints separate from native resolver environments: known GitHub/SSH credentials must reach native resolve/update and SwifterPM cold paths. SwifterPM's warm no-fetch lockfile validation uses the manifest environment so rotating credentials do not invalidate native manifest caches. Native fetching evaluates manifests with credentials too; manifests intentionally depending on them must opt in through includes or `.all`. Explicit includes win over all exclusions; explicit exclusions also apply to native resolution.
