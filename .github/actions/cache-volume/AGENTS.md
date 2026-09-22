# Cache volume action

This is the source package for the standalone `tuist/cache-volume` action.
The release workflow is `.github/workflows/cache-volume-action.yml`.

- Keep the distribution self-contained: root `action.yml`, `attach.sh`, README,
  license and source commit. Never require a checkout of the monorepo to run it.
- Pass workflow inputs as quoted environment-backed arguments, never shell code.
- Preserve the installed client's cold fallback, output and error behavior.
- Run `python3 -m unittest discover -s .github/actions/cache-volume -p '*_test.py'`.
- Publish only reviewed main-branch versions after live storage validation;
  immutable version tags must not be replaced. `v1` is the moving release alias.
- Provider integration implementation and rollout live in `infra/runners-controller/cache-volume-integrations.md`.
