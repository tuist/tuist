# Cache volume action

This is the source package for the standalone `tuist/cache-volume` action.
The release workflow is `.github/workflows/cache-volume-action.yml`.

- Keep the distribution self-contained: root `action.yml`, `attach.sh`, README,
  license and source commit. Never require a checkout of the monorepo to run it.
- Pass workflow inputs as quoted environment-backed arguments, never shell code.
- Preserve the installed client's cold fallback, output and error behavior.
- Run `bash .github/actions/cache-volume/action_test.sh`.
- Relevant main pushes automatically release all three provider wrappers through
  `release:check cache-volume`. Immutable tags must not be replaced; major tags
  move forward. Wrapper releases and live storage fleet enablement are separate.
- Provider integration implementation and rollout live in `infra/runners-controller/cache-volume-integrations.md`.

- Document ordinary bind-mounted directories and preserve the absent/empty target
  contract. `key` stays single-line; `path` takes one path per line (blank lines
  ignored, surrounding whitespace trimmed) and `attach.sh` passes one `--path`
  per line from a Bash array. A single-line `path` behaves as one `--path`.
  Keep the wrapper compatible with macOS `/bin/bash` 3.2. The installed
  client and controller own mounting; never add workflow sudo or symlink helpers.

- macOS uses symlink targets and rejects node_modules; preserve its documented limitations.
- macOS custom volumes retain automatic built-in Tuist/CAS caches. They reuse the
  shared runner-cache lifecycle with an APFS backend; rollout and compatibility
  are documented in `infra/tart-kubelet/custom-cache-volumes.md` at repository root.
