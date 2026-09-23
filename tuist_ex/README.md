# Tuist for Elixir

Package skeleton for the future Tuist integration with Mix and ExUnit.
Build instrumentation, test reporting, uploading, and dashboard integration are
not implemented yet.

## Development

Requires Elixir 1.18 or later. From `tuist_ex/`:

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix hex.build
mix docs --warnings-as-errors
```

[Quokka](https://github.com/emkguts/quokka) is configured as a formatter plugin.
`mix format` applies its fixes; `mix format --check-formatted` enforces them in
automated checks. [Mimic](https://hexdocs.pm/mimic) is available for test mocks.
Register modules with `Mimic.copy/1` in `test/test_helper.exs` as tests are added.
The skeleton intentionally contains no implementation modules or test cases.

## Automated checks and releases

The check workflow runs compilation, documentation, tests, formatting, and
package assembly as separate jobs. Compilation checks Elixir 1.18 and the
repository's current Elixir version; the other jobs use the current version.

The `tuist-ex` release component uses `tuist-ex@` tags and scoped commits such as
`feat(tuist-ex): add build instrumentation`. On `main`, the release workflow
checks for a version bump, runs the same validation, publishes the package and
documentation to Hex, and creates a GitHub release. Publication is serialized
and never cancelled mid-release. If package publication succeeds but the GitHub
release fails, a retry verifies the published package contents and resumes
documentation and release creation without replacing the package. Manual releases are restricted to `main`.

The release workflow sets the package version from the shared release checker;
the version in `mix.exs` is the development baseline. Release notes are generated
from scoped commits using `cliff.toml`.

Publication reuses the repository's `HEX_API_KEY` secret, which also publishes
Noora. Its Hex account must be the intended owner of `tuist_ex` and the key
must have package publishing permission. The first publication requires the
package name to be available. `TUIST_RELEASE_GITHUB_TOKEN` is used for GitHub
releases when available, with the workflow token as the fallback.
