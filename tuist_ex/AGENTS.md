# Tuist Elixir integration

This independently published Hex package provides `mix tuist.login` with browser,
email/password, and continuous integration authentication, `mix tuist.test`
which installs an ExUnit formatter and posts a test-run payload to
`POST /api/projects/:acc/:proj/tests` with `build_system: "mix"`, and
`mix tuist.compile` which attaches an after-compiler hook to Mix's Elixir and
app compilers and posts a compile record with per-diagnostic granularity to
`POST /api/projects/:acc/:proj/mix/builds`. `CompileProfile` adds the per-file
profile: compile and wait durations come from the compiler's `--profile time`
output, while a tracer timestamps when each file started and each module
became available. Offsets are milliseconds from the start of the compile. A
wait is placed right before the module it waited on became available; when
that moment was not observed its offset stays `nil` rather than being guessed.
Both tasks take the command line of the task they wrap (`Args.split/2` keeps
only their own options), so projects alias them as `test` and `compile`.
`Args.run_wrapped/3` exists because of that alias: called by its own name, a
Tuist task would follow the alias back to itself and Mix would do nothing.
`mix tuist.compile` must never write the shared `:analytics_options`; under
the alias it runs inside `mix tuist.test`, which owns them. A compile with no profiled files is not reported unless a compiler or diagnostic indicates failure, since compilers can return `:ok` without doing any work. Retries (`--retries`,
`TUIST_TEST_RETRIES`, `tuist: [test_retries:]`) rerun failed tests with
`mix tuist.test --failed` in a child process whose formatter writes outcomes
to a file instead of submitting; the parent runs the suite with `--raise` so
a passing retry can turn the exit code green, merges the attempts as
repetitions and submits once. Sharding (`Shards`, `mix tuist.test.build`) plans with ExUnit modules, since
that is what runs report timings for, discovered by parsing the test files
without loading them, and runs test files, since that is what Mix can
select. The build archive lists symbolic links instead of storing them,
because `:erl_tar` refuses to extract a link that leaves the directory and
every dependency's `priv` does; links are recreated only when they stay
inside the checkout. A shard that cannot fetch its plan fails rather than
running everything. The downloaded build is unpacked beside the build
directory and swapped in whole, and a link is recreated only below real
directories and pointing inside the checkout. Retries never recover a suite
that `--max-failures` cut short (the formatter notes `:max_failures_reached`),
forwarded arguments are never deduplicated, and a Tuist task started outside
the test environment re-executes itself in it (`Args.ensure_env/3`) because
switching `Mix.env` after the task was found leaves `dev`'s dependency paths
loaded. `CompileReporter` stops after each build and trims a build to the
server's limits (see `Tuist.Mix.limits/0`) rather than have it refused. The tracer also records every reference a file makes to another module,
deduplicated in its own table because they arrive by the million, and
`CompileProfile` turns them into the project's file dependency graph with
`mix xref`'s kinds (`compile`, `export`, `runtime`). Only project files are
kept; a module not compiled in this run is resolved through its compiled file
in the build directory. The same profile output also reports work around the files (type checking,
writing modules to disk); a line is printed when its work ends, so its arrival
time minus its duration is the start. Other Mix compilers are timed from
`after_compiler` hooks: each starts when the previous one finishes, so the
first compiler in the list has no known start and is not reported.
`MachineMetrics` samples CPU and memory through Erlang's operating-system
monitor and network and disk throughput (bytes per second) from the
machine-wide counters in `IOCounters`: `/proc` on Linux, `netstat` and `ioreg`
on macOS, since Erlang has no direct binding for those. Always pass `-n` to
`netstat`; without it the command resolves names and can take seconds. It shares the Tuist credential
file and uses the command line tool's refresh lock path. Server ingestion and
dashboard presentation belong in `server/`.

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
- Nothing in the analytics code is found by a global name, so its tests run
  `async: true`: a `CompileReporter` is an unregistered process its caller
  holds; a `CompileProfile` is a handle passed to every function, and only
  `install/2` touches what belongs to the whole VM (the compiler's tracers,
  standard error, and the one profile the tracer writes to); the formatter
  hands a deferred run to its owner as a message; `MachineMetrics` takes what
  it samples as options. Tests give payload builders a fixed environment so
  none of them asks git about the checkout. Keep it that way: a test that
  needs `async: false` is a sign that state leaked somewhere global, and
  `compile_profile_install_test.exs` is the one place that is expected.
- Validate with `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test --warnings-as-errors`, `mix hex.build`, and `mix docs --warnings-as-errors`.
- The user guides are the Elixir pages under `server/priv/docs/en/guides/`
  (`install-hex-package.md`, `get-started/elixir-project.md`, and `elixir.md` under
  build insights, test insights, flaky tests and test sharding). A change to
  an option, an environment variable or what a task prints belongs there too,
  and every command on those pages was run before it was written down: run it
  again before you change it.
- `mix tuist.test --prepare-only` downloads a shard's uploaded build without starting the app or tests. Run any database setup in a separate process, then `--no-download` uses the prepared build (and fails when the application artifact is absent). Both flags require a shard index and cannot be combined. Keep `MIX_ENV=test` on cold bootstrap commands. `--scheme LABEL` identifies execution variants in the existing test-run scheme field, keeping different environments out of cross-run flakiness comparisons. Flags remain local to the wrapper, never forwarded to `mix test`.
- Releases use the `tuist-ex` conventional commit scope and `tuist-ex@` tags.
  See `.github/workflows/tuist-ex-release.yml` and the shared release component registry.
