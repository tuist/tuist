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
select. Each reported module carries an `execution_mode` (`parallel` for
`async: true`, `serial` otherwise, from the test's `:async` tag). The plan
request declares `concurrent_modules`, the units whose module says
`use ..., async: true`, read from the same parse, as the Xcode CLI declares
`parallelizable_modules`; the server measures how many ran at once from
earlier shards' reported modes and durations, and balances the shards' wall
clock rather than their summed module durations. The build archive materializes dependency `deps/*/priv` directories whose
real paths stay inside the checkout, including native libraries generated in
`deps/` that are absent on cold workers. Preserve project `priv` links so nested
checkout-relative resources (such as published agent skills) keep their original
base directory. Other symbolic links travel as a list,
because `:erl_tar` refuses escaping links; links are recreated only when they
stay inside the checkout. Do not follow nested or ancestor symlinks when
materializing `priv`, which could package files outside the checkout. A shard that cannot fetch its plan fails rather than
running everything. The downloaded build is unpacked beside the build
directory and swapped in whole, and a link is recreated only below real
directories and pointing inside the checkout. Retries never recover a suite
that `--max-failures` cut short (the formatter notes `:max_failures_reached`),
forwarded arguments are never deduplicated, and a Tuist task started outside
the test environment re-executes itself in it (`Args.ensure_env/3`) because
switching `Mix.env` after the task was found leaves `dev`'s dependency paths
loaded. That process and the retries run through `Subprocess.run/3`, which
hands them this process's terminal; do not relay their output through
`System.cmd/3`, whose byte chunks can split a UTF-8 character and crash the run. `CompileReporter` stops after each build and trims a build to the
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
`netstat`; without it the command resolves names and can take seconds.
While Mix compiles dependencies it prunes the OTP code paths, even for
applications that are already running, and `Application.ensure_all_started/1`
does not restore them. Put every OTP application used from a task back on the
path with `Mix.ensure_application!/1` before starting it (`:inets` and `:ssl`
in `TuistEx.HTTP`, `:os_mon` in `MachineMetrics`). It shares the Tuist credential
file and uses the command line tool's refresh lock path. With `--cover`, `mix tuist.test` reports line coverage (`Analytics.Coverage`)
with every run, and on CI or with `--cover` the Git history (`Analytics.GitHistory.enabled?/2`, off with
`TUIST_GIT_UPLOAD_ENABLED=false`), so the formatter runs in `{:defer, owner}`
mode then. The formatter reads the counters at
`suite_finished`: every test has run, and Mix's coverage tool has neither
written its report nor, in an umbrella, restarted `cover` for the next
application. A run is
partial only when its own arguments pick tests; the files a shard appends are
not counted. Every `--cover` run, sharded or not, counts natively: it compiles
the project as `mix test` would, recompiles the modules from their debug info
with `line_coverage` (`Coverage.instrument/1`; the Elixir compiler skips the
pass that adds the counters), keeping chunks only Elixir writes and skipping
modules that already carry the counters, so `mix tuist.test.build --cover`
does it once for every shard. It then switches the runtime to line
counters (`Coverage.enable_native/1`: `code:set_coverage_mode/1` applies after
boot only to explicitly loaded code, so every module of the build is loaded
then, before the application starts) and drops Mix's `--cover` and
`--export-coverage`. It then does what Mix's tool would print and enforce
itself: the formatter reads `Coverage.module_lines/1` at `suite_finished`
(Mimic swaps its copies back after the suite) into the deferred payload, and
the task prints Mix's per-module summary (`Analytics.CoverageSummary`) after
the run and registers `exit({:shutdown, 3})` below `summary: [threshold: N]`
(90 by default; `summary: false` turns both off); shards get neither, retries
keep the first run's counts, and a project setting `:output` is warned that no
HTML is written. An
umbrella's root, a runtime without the JIT, and a project that sets its own
`test_coverage` tool (excoveralls) keep Mix's tool and read `cover`'s
counters; a shard doing so exports instead of meeting the threshold. The
formatter's `init`, which runs after the test helper and before any test,
cover compiles only the modules Mimic marked to copy (`Mimic.Coordinator` on
Mimic 2.4+, `Mimic.Server` before) and has Mimic swap them right away
(`Mimic.calls(module, :module_info, 0)`), as `Mimic.copy` does for a module
Mix's tool already compiled: at a later first stub, Mimic would export the
calls made before it until after the suite (Mimic carries a cover compiled
module's counts across its swaps, while a reload resets native counters), and the snapshot merges `cover`'s counts with the native ones of
every other module of the build, loading those the run never did. Paths are relative to the Git root, a build compiled elsewhere is
matched by path suffix, the OTP application is the target, and files under the
test paths are test code. A line belongs to the function whose clause head
starts closest above it. Generated functions (`__*`, `module_info`), such as
those on a `defmodule`, `schema` or `use` line, are not listed, but their
lines still count for the file, as `cover` and Mix count them; the file page
says how many covered lines no listed function owns. Coverage that compresses past the server's inline
threshold is uploaded first (`/tests/coverage/uploads`). Retries never carry
`--cover`. `mix tuist.coverage.complete` signals the commit's coverage
complete, as `tuist coverage complete` does. Tests that start or stop `cover`
must leave a running cover server alone: under `mix test --cover` it is Mix's.
On a pull request's merge ref (`refs/pull/N/merge`), `Env.git_commit_sha/2`
reports HEAD^2, the pull request's head, as the command line tool does, since
the merge commit exists only in the checkout; a shallow checkout without that
parent reports HEAD. When `GITHUB_SHA` (GitHub's merge commit) is set and is
not HEAD, the workflow checked out another commit, and HEAD is reported.
`GIT_COMMIT` still wins.
`Git` and `Analytics.GitHistory` port the command line tool's Git history
collection (`GitController+History.swift`, `GitHistoryParser.swift`,
`GitHistoryService.swift`) and must stay in step with it, since the server
compares what both report: the merge base with the CI provider's base branch,
the base branch's commit, the commits within the window reachable from the
head and from that commit when the checkout has it (a shallow boundary's
parents read from the commit objects), and whether the checkout is dirty
(`git status --porcelain`, untracked files included). What reaches the remote
is `Git.history/4`'s `remote_access`: `:history` only with `--cover` (the base
branch fetched and a shallow clone deepened within the server's budget until
the merge base is found), `:base_head` otherwise (a checkout without the base
branch gets its latest commit from one `git ls-remote`, killed at the budget),
`:none` with `TUIST_GIT_UNSHALLOW_ENABLED=false`. Every remote call is a round
trip whatever it transfers, which is why only coverage fetches.
`GitHistory.publish/2` sends the commits the server lacks and the branch heads
(the run's, and the base branch's when it differs, listed or not: it is how
the default branch's head advances between its own runs) before the runs are
submitted, since ingestion reads which commits the default branch reached;
`GitHistory.upload_listing/2` sends a clean checkout's file listing after
them, only with `--cover`. Git's standard error is discarded and nothing here ever fails a run.
Server ingestion and
dashboard presentation belong in `server/`.

- `lib/tuist_ex/analytics/contract.ex` carries the wire contract version the
  plugin was built against. Bump it whenever the payload gains a required field
  or a semantic change downstream would misread an older client's shape.
- `lib/tuist_ex/analytics/ex_unit_formatter.ex` is a `GenServer` implementing
  ExUnit's formatter callbacks. Submission failures are logged through the
  passed shell function and swallowed. A submission failure never changes the
  exit code of `mix test`.
- `Auth.reporting_token/1` allows missing credentials only for explicit private-destination opt-in (`TUIST_NETWORK_TRUSTED_PUBLISHING`, runtime/project config). Explicit environment false overrides config. Present files/tokens and supplied CI OIDC must authenticate or fail, never downgrade; preserve corrupt/rejected credentials. Share destination resolution with analytics, including umbrella root `project_config`. Normalize credential filename host case/trailing dots, inspect legacy aliases, and fail closed on unreadable directories rather than interpreting inspection errors as absence. Only POST `/tests` and `/mix/builds` use this resolver. Strip privileged references from unsigned payloads and skip coverage/history uploads before they are attempted; preserve local coverage and authenticated behavior. Reads, shards and archives retain ordinary authentication.
- `Analytics.Actor` adds an optional, unverified `x-tuist-actor-id` only to build/test report POSTs. Resolve explicit `TUIST_ACTOR_ID`, runtime `:actor_id`, then project `:actor_id`. Never infer usernames or send a claim by default. Empty/invalid overrides omit the claim instead of falling back. Attribution never changes `Auth.token/1`, endpoints, JSON bodies or upload/read/shard requests; older servers ignore this header.
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
  `compile_profile_install_test.exs` and `http_test.exs` (which prunes the
  VM's code path) are the places where it is expected.
- `TuistEx.Auth.token/1` tries `TUIST_TOKEN`, then the stored credentials, then
  an OpenID Connect exchange on GitHub Actions, CircleCI or Bitrise, so CI needs
  no login step. The exchanged token is kept in memory for the VM and never
  written to the shared credentials file: a runner that outlives the job would
  otherwise hand it to the next repository's job. Every failure on that path is
  an `{:error, message}`, never a raise, because reporting must stay silent.
- Validate with `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix test --warnings-as-errors`, `mix hex.build`, and `mix docs --warnings-as-errors`.
- The user guides are the Elixir pages under `server/priv/docs/en/guides/`
  (`install-hex-package.md`, `get-started/elixir-project.md`, and `elixir.md` under
  build insights, test insights, flaky tests and test sharding). A change to
  an option, an environment variable or what a task prints belongs there too,
  and every command on those pages was run before it was written down: run it
  again before you change it.
- `mix tuist.test --prepare-only` downloads a shard's uploaded build without starting the app or tests. Run any database setup in a separate process, then `--no-download` uses the prepared build (and fails when the application artifact is absent). Both flags require a shard index and cannot be combined. Keep `MIX_ENV=test` on cold bootstrap commands. `--scheme LABEL` identifies execution variants in the existing test-run scheme field, keeping different environments out of cross-run flakiness comparisons. Flags remain local to the wrapper, never forwarded to `mix test`.
- Dependency caching is enabled with `tuist: [cache: true]`, selecting all structurally supported dependencies by default. Keyword options preserve automatic selection; `dependencies:` optionally restricts it and `exclude:` takes precedence. Absent/false/nil disables caching. Automatic structural selection does not prove hermeticity; additional macro inputs and mandatory side effects remain the user's responsibility. It runs before the wrapped compile. It uses Bazel's shared REAPI ActionCache/CAS, project-scoped token exchange, endpoint discovery and Kura analytics; a verified local snapshot is the fail-open fallback. Honor `TUIST_CACHE_ENDPOINT` ahead of project endpoints and discovery, including operator-selected private plaintext endpoints; only the environment override relaxes the default HTTPS-or-loopback policy. Routing overrides do not affect artifact keys. Transport invariants live in [lib/tuist_ex/cache/reapi/AGENTS.md](lib/tuist_ex/cache/reapi/AGENTS.md). Use `mix tuist.setup --project account/project` for setup. It installs the ordinary three-step compile bootstrap and `tuist.test` aliases, preserves other aliases/options and standard Phoenix test preparation, and refuses unsupported custom actions or source shapes. Dynamic alias expressions must retain environment-specific test preparation rather than capturing setup's current environment. The source editor uses AST token locations, preserves comments, formats/validates before writing, and atomically replaces regular files while retaining permissions. No SDK function capture or evaluation snippet belongs in the quick-start. External SDK function captures are not cold-safe: OS workers do not load SDK modules in the parent. `compile.exs` remains packaged only for compatibility with the earlier evaluation alias; setup migrates that exact form without executing it. Use this alias to compile Tuist and its transport dependencies before other dependencies. The wrapper re-enables Mix's `deps.loadpaths` and `loadpaths` after cache preparation, preserving checks and local-chain compilation. Finish normal dependency loading before installing the application compiler tracer, and restore pre-existing code paths before reporter cleanup on both success and failure. Unselected fetched dependencies compile in batches. Transport channels own their process flags/links in supervised workers, not the compiler process. `upload: false` disables remote publication but is not an authorization boundary; cache writers remain trusted code producers. `DependencyCache` keeps compiler failures outside fail-open cache boundaries. Artifact/input invariants live in [lib/tuist_ex/cache/AGENTS.md](lib/tuist_ex/cache/AGENTS.md). The compile reporter emits dependency observations even for cache-only builds, but leaves ordinary idle builds unreported. Shared package setup belongs in `server/priv/docs/en/guides/get-started/elixir-project.md`; cache/build/test feature guides link back instead of duplicating aliases. The cache usage guide is `server/priv/docs/en/guides/features/cache/elixir.md`; input, portability and protocol details belong in `elixir-advanced.md` alongside it.
- Cold sharding build jobs must enter through the generated compile alias with `MIX_ENV=test mix compile` before invoking `mix tuist.test.build`. Discovering an unloaded SDK task can compile dependencies before caching starts. Bootstrap regression tests cover both the ordinary alias and the legacy script in fresh test-environment VMs with parallel dependency compilation, and require a snapshot to be published and restored after deleting `_build`. The ordinary-alias test then discovers `tuist.test.build` in another process and verifies that it does not compile the cached dependency again; the legacy variant retains plain `mix compile` coverage.
- Cache key input modeling traverses structs as maps without requiring `Enumerable`. Model regex configuration by source and options, not its compiled pattern, which can contain VM-local references on OTP 29. Other opaque runtime values still bypass caching. Keep cross-VM restore and regex source/options invalidation covered in `dependency_cache_test.exs`.
- Mix task entry points and safe project setup: see [lib/mix/tasks/AGENTS.md](lib/mix/tasks/AGENTS.md).
- Releases use the `tuist-ex` conventional commit scope and `tuist-ex@` tags.
  See `.github/workflows/tuist-ex-release.yml` and the shared release component registry.
