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

- Document symlink target limitations, node_modules rejection, single-line paths,
  and workspace .gitignore rules without trailing slashes in the public README.
