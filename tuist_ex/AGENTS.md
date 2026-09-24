# Tuist Elixir integration

This independently published Hex package provides `mix tuist.login` with browser,
email/password, and continuous integration authentication, and `mix tuist.test`
which installs an ExUnit formatter and posts a test-run payload to
`POST /api/projects/:acc/:proj/tests` with `build_system: "elixir"`. It shares
the Tuist credential file and uses the command line tool's refresh lock path.
Compile analytics (`mix tuist.compile`) land in a separate release. Server
ingestion and dashboard presentation belong in `server/`.

- `lib/tuist_ex/analytics/contract.ex` carries the wire contract version the
  plugin was built against. Bump it whenever the payload gains a required field
  or a semantic change downstream would misread an older client's shape.
- `lib/tuist_ex/analytics/ex_unit_formatter.ex` is a `GenServer` implementing
  ExUnit's formatter callbacks. Submission failures are logged through the
  passed shell function and swallowed. A submission failure never changes the
  exit code of `mix test`.
- Options resolved by `TuistEx.Analytics.Config` mirror `TuistEx.Auth`: env
  overrides beat runtime options beat `Mix.Project.config()[:tuist]`.

- Quokka runs through `mix format`; use `mix format --check-formatted` for checks.
- Use Mimic for mocks. Register copied modules in `test/test_helper.exs`.
- Do not change shared environment variables in tests; use dependency injection
  or pass environment overrides to subprocesses.
- Validate with `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test --warnings-as-errors`, `mix hex.build`, and `mix docs --warnings-as-errors`.
- Releases use the `tuist-ex` conventional commit scope and `tuist-ex@` tags.
  See `.github/workflows/tuist-ex-release.yml` and the shared release component registry.
