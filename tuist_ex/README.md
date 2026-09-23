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

The check workflow validates formatting, compilation, tests, package assembly,
and documentation on Elixir 1.18 and the repository's current Elixir version.

The `tuist-ex` release component uses `tuist-ex@` tags and scoped commits such as
`feat(tuist-ex): add build instrumentation`. On `main`, the release workflow
checks for a version bump, runs the same validation, publishes the package and
documentation to Hex, and creates a GitHub release. Publication is serialized
and never cancelled mid-release. Manual releases are restricted to `main`.

The release workflow sets the package version from the shared release checker;
the version in `mix.exs` is the development baseline. Release notes are generated
from scoped commits using `cliff.toml`.

Publication uses the repository's existing `HEX_API_KEY` secret, which must have
permission to publish `tuist_ex`. The first publication also requires the package
name to be available or owned by Tuist. `TUIST_RELEASE_GITHUB_TOKEN` is used for
GitHub releases when available, with the workflow token as the fallback.
