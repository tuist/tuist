# Tuist Elixir integration

This independently published Hex package provides `mix tuist.login` with browser,
email/password, and continuous integration authentication. It shares the Tuist
credential file and uses the command line tool's refresh lock path. Build and ExUnit
instrumentation are future work. Server ingestion and dashboard presentation
belong in `server/`.

- Quokka runs through `mix format`; use `mix format --check-formatted` for checks.
- Use Mimic for mocks. Register copied modules in `test/test_helper.exs`.
- Do not change shared environment variables in tests; use dependency injection
  or pass environment overrides to subprocesses.
- Validate with `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test --warnings-as-errors`, `mix hex.build`, and `mix docs --warnings-as-errors`.
- Releases use the `tuist-ex` conventional commit scope and `tuist-ex@` tags.
  See `.github/workflows/tuist-ex-release.yml` and the shared release component registry.
