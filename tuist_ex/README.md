# Tuist for Elixir

This package connects an Elixir project to Tuist: it reports your test runs
and builds to the dashboard, flags flaky tests, and splits a test suite across
machines. It adds `mix tuist.login`, `mix tuist.test`, `mix tuist.compile` and
`mix tuist.test.build`, and writes to the same Tuist server the command line
tool and the Gradle plugin use.

The guides live in the Tuist documentation: start with
[Elixir project](https://tuist.dev/en/docs/guides/get-started/elixir-project), and
see [Install the Hex package](https://tuist.dev/en/docs/guides/install-hex-package)
for every option.

## Configure the server and project

You can share the Tuist server address and the project handle with your team
in `mix.exs`:

```elixir
def project do
  [
    app: :my_app,
    tuist: [
      url: "https://tuist.example.com",
      project: "your-account/your-project"
    ]
  ]
end
```

`TUIST_URL` and `TUIST_PROJECT` override those values, as they do in the Tuist
command line tool. `--url` and `--project` are also accepted when the env
overrides are unset. The default URL is `https://tuist.dev`.

## Log in

```sh
mix tuist.login
mix tuist.login --email person@example.com --password secret
mix tuist.login --url https://tuist.example.com
```

Without credentials, the task opens a browser and waits for authorization. If
you provide only `--email` or `--password`, it prompts for the missing value.
On a continuous integration provider, it exchanges an
[OpenID Connect](https://openid.net/developers/how-connect-works/) identity token
from GitHub Actions, CircleCI, or Bitrise, matching the Tuist command line flow.
On those providers a login step is optional: when no other credentials are
available, the reporting tasks make the same exchange the first time they need
a token. On GitHub Actions the job needs the `id-token: write` permission.

Credentials are saved under the Tuist configuration directory. The task writes
them atomically with access restricted to the current user. Refreshes take a
lock at the Tuist command line tool's lock path and reread the file before
exchanging the refresh token, so parallel processes do not refresh the same
token twice.

## Run tests with analytics

```sh
mix tuist.test
mix tuist.test --project your-account/your-project
mix tuist.test --trace        # forwards --trace to mix test
```

`mix tuist.test` installs an ExUnit formatter alongside the default one and
runs `mix test`. When the suite finishes, it POSTs a summary of the run,
each module, each suite (from `describe` blocks), and each test case,
including failure messages and source locations, to the Tuist server. Test
timings are converted from microseconds to milliseconds. Every argument
other than the task's own (`--url`, `--project`, `--retries`) is forwarded to
`mix test` verbatim.

Elixir, [OTP](https://www.erlang.org/doc/system/otp), `Mix` environment, the
current git ref, and any recognised continuous integration provider metadata
travel with the payload so a dashboard can group runs by branch, commit, and
CI run.

Analytics submission never changes the exit code of `mix test`. If a request
fails, set `TUIST_DEBUG=1` to print the reason to standard error. Authentication
uses the `TUIST_TOKEN` environment variable if set, then the credentials from
`mix tuist.login`, then an OpenID Connect exchange on a supported continuous
integration provider.

## Keep using `mix test` and `mix compile`

Run the shared setup once:

```sh
mix tuist.setup --project your-account/your-project
```

Commit the updated `mix.exs`. Setup enables dependency caching and installs both
compile and test integration, preserving other options and standard Phoenix test
preparation. It refuses unsupported custom actions instead of removing them.
Retries and CI sharding remain opt-in. No evaluation snippets or script paths are
needed; see [Get started with Elixir](https://tuist.dev/en/docs/guides/get-started/elixir-project).

`mix test test/my_test.exs:12 --trace` then runs and reports exactly as
`mix tuist.test` would. The alias also gets the environment right: Mix runs
`mix test` in the test environment, whereas a task typed as `mix tuist.test`
starts in `dev` and has to start over in a new process. If you call the tasks
by name, set `MIX_ENV=test` or add
`preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]` to
`def cli` in your `mix.exs`. Aliasing `compile` covers every compile, including
the ones `mix test` or `mix phx.server` trigger; a compile that finds nothing
to do is not reported.

## Cache compiled dependencies

Enable dependency caching with `cache: true` to select supported dependencies
automatically. It uses the same
Kura REAPI ActionCache and CAS/ByteStream protocol as Bazel: an input key maps
to an ActionResult whose output is a content-addressed dependency compilation
bundle. A verified local snapshot store remains the fail-open fallback. The
shared setup above enables this alongside build and test insights. `mix compile`
restores matching dependency builds before Mix compiles the rest. The generated alias exposes compiled bootstrap modules without compiling other
dependencies, including when Mix uses separate OS compiler workers. The wrapper
re-enables Mix's normal dependency checks afterward, so local dependencies and
unsupported chains still compile and changed locks are checked. Non-allowlisted
fetched dependencies compile in batches, retaining Mix's OS-worker parallelism.
Without an
alias, use `mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.compile`.
Dependencies needed to bootstrap Tuist itself compile normally and, when already
current, do not produce cache lookups. Jason and Decimal are bootstrap
dependencies, so they are not useful demonstration allowlist entries; replace
any restore demonstration with dependencies your project actually uses.
A standalone `mix tuist.compile` may compile dependencies while discovering the
task, before caching is available. It caches fetched, pure Elixir dependencies,
not the project's own code. Native and custom compilers, local dependencies,
and inputs it cannot model compile normally. Dependencies Mix already considers
up to date need no lookup and are not counted as hits.

Declare extra compile-time file or directory inputs with `inputs: ["path"]`
and environment-variable names with `env: ["NAME"]` in `cache`. Source contents,
locked dependency identities, upstream sources and BEAMs, effective application
configuration (explicit configured keys, with application defaults covered by
dependency sources), dependency and VM-wide compiler options, dependency-specific
`env:` and `system_env:`, Mix environment/target,
and the Elixir build, full OTP version (when available), ERTS, compiler bytecode,
OS version, architecture, word size and byte order enter the key. Standard
compiler/runtime inputs (`ERL_COMPILER_OPTIONS`, `ELIXIR_ERL_OPTIONS`, `ERL_AFLAGS`,
`ERL_FLAGS`, `ERL_ZFLAGS`, `SOURCE_DATE_EPOCH`, `ERL_LIBS`, `MIX_PATH`, and `MIX_ARCHIVES`) are included automatically;
declare other compile-time environment variables explicitly. Inputs and effective
configuration are captured before each dependency lookup and rechecked before
publishing, so an earlier compilation cannot leave later lookups using stale inputs. Custom global tracers bypass
caching so their side effects are not skipped.

Elixir macros can read arbitrary inputs. Declare additional inputs, exclude
non-deterministic dependencies with `exclude: [:dependency]`, or restrict selection
with `dependencies: [:dependency]` when you need an audited allowlist. This is not automatic hermetic
input discovery; changing undeclared external inputs can still make a bundle stale.

Verified local snapshots are tried before the remote cache. Idle builds and
builds fully served locally do not contact cache endpoints or resolve credentials.
A compile lazily opens one remote session, closes it even on compiler failure,
and enforces a 30-second client RPC deadline independently of the server.

Remote caching uses the existing account endpoint discovery and project-scoped
cache-token exchange. Kura reports signed action-cache and CAS analytics with
`client_kind: "mix"`, the Mix build ID and dependency name. There is no separate
Mix storage or analytics API. Clients request best-effort inlining of bundles up
to 128 KiB in Kura's ActionCache response to avoid a second round trip. Endpoints
that ignore these hints, larger bundles, and omitted contents use ByteStream.
Both paths verify the bundle's declared size and SHA-256 before installation.
On OTP 28 and later, clients negotiate zstd with the
server for ByteStream transfers of at least 1 KiB. Incompressible uploads, older
OTP runtimes and endpoints without compression use identity transport. CAS digests
and reported transfer bytes always describe the uncompressed bundle. Set
`remote: false` for local-only caching;
`endpoint:` can select a self-hosted HTTPS REAPI endpoint (HTTP is limited to
loopback development hosts). Authentication, unavailable
endpoints, quota refusals and storage failures fall back without hiding compiler
failures. Set `upload: false` to read remote bundles without publishing new ones;
local snapshots still populate. This is a client behavior option, not an
authorization boundary. Dependency snapshots and remote bundles are capped at 64 MiB. Compiler manifests and BEAMs
may embed producer checkout paths and compile-time values, including secrets.
Audit selected dependencies and restrict project cache access accordingly.
Writers are trusted code producers: a writer can publish executable BEAMs under
computed keys. Digest verification detects corruption, not malicious producers.
Do not provide cache-write credentials to untrusted branches or dependencies.

The local fallback is stored under the user's Tuist cache directory; `path:` selects a
different location. Checkout paths are keyed by default. `portable: true` enables
reuse across checkouts, but cached BEAMs retain producer paths, including
compile-time `__DIR__`, `__ENV__.file`, and `File.cwd!()` values. Only enable it
for dependencies whose behavior does not rely on those paths. Resource links
are recreated for the current dependency checkout. Upstream BEAMs still enter
portable keys and can embed absolute paths, so cross-checkout hits may require
restoring the upstream dependency closure from the same cache too.

The **Mix Cache** dashboard shows average/percentile hit rates, cache I/O and
recent builds. Successful REAPI operations report actual CAS payload bytes and
client transfer durations with `read_source`/`write_source` set to `remote`;
local fallback operations report `local` provenance, copied artifact and
manifest bytes and verification/installation durations. Neither includes
compilation or linked source resources. Legacy and failed observations remain
unavailable rather than becoming measured zero.
Open a build's **Mix cache** tab for task hits/misses, hit rate and transfer
totals. Expanded tasks show only their real CAS output rows and digest links;
diagnostics and measurement provenance remain in the analytics records.
**CAS Outputs** uses Bazel's shared REAPI analytics queries and Kura-signed
records for its download/upload graph, time-weighted throughput widgets,
searchable/sortable table and copyable content hashes. Local-only builds do not
invent remote outputs or throughput. Compressed sizes are not reported.
Estimated compilation time avoided is the original compilation duration, not
elapsed build time saved. Cache-only compiles are reported too. There is no
automatic eviction for the local fallback store; Kura uses its existing shared
cache retention and eviction. See [Elixir cache](https://tuist.dev/en/docs/guides/features/cache/elixir)
for the full behavior and limitations.

## Detect flaky tests with retries

ExUnit runs each test once, so a test that fails intermittently looks the same
as a broken one. Turn retries on and the tests that failed are run again with
`mix test --failed`, in a fresh process, up to the number of times you set:

```elixir
tuist: [project: "your-account/your-project", test_retries: 2]
```

`--retries 2` and `TUIST_TEST_RETRIES=2` do the same for one invocation. A
test that passes on a retry is reported with every attempt and shows up as
flaky in the dashboard, and the command succeeds if every failed test
eventually passes. Retries are off by default, in which case the exit code is
always that of `mix test`.

A run that `--max-failures` cut short is never retried: the tests it did not
reach are unknown, so the run is reported as it is and stays failed.
Retries are also skipped with `--warnings-as-errors`, which `mix test` would
no longer enforce, and from an umbrella's root: run the tests inside one of
its applications to retry them.

Without retries, Tuist still flags a failure as flaky when the same test has
also passed on the same commit in continuous integration, for example after
someone reruns a failed job.

## Build once, test on several machines

Sharding splits your tests across machines, balanced by how long each test
module took in earlier runs, and reports them as one test run. Only one
machine compiles; the others download its build.

On one machine, once per pipeline:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 4
```

The first command enters through the generated compile alias so dependency
caching runs before Mix discovers the sharding task. On a cold checkout,
direct task discovery can compile dependencies before Tuist can cache them.
Keep both commands in the test environment.

This compiles the project for testing, asks Tuist to split the test files
into at most four shards, and uploads the `_build/test` directory. A test file
runs as a whole and is planned under the first module it defines; a file that
cannot be parsed stops the plan, since the suite could not run either. On GitHub
Actions it writes `matrix={"shard":[0,1,2,3]}` to the job outputs; elsewhere
it writes the plan to `.tuist-shard-matrix.json`.

Then on each shard, after checking out the code and running `mix deps.get`:

```sh
TUIST_SHARD_INDEX=0 mix tuist.test
```

or plain `mix test` if you aliased it. The task downloads the build, runs
only that shard's test files without compiling, and reports the results.
Shards need the same Elixir and Erlang versions as the machine that built.

The shards find their plan by a reference derived from the pipeline run on
GitHub Actions, GitLab, CircleCI and Buildkite. Anywhere else, set
`TUIST_SHARD_REFERENCE` to the same value on every machine. Pass `--no-upload`
to `mix tuist.test.build` if you would rather have each shard compile.

Test paths given on a shard's command line narrow what that shard runs. Run
both commands inside an application: sharding from an umbrella's root is not
supported yet.

## Report code coverage

Pass `--cover` to `mix tuist.test` and the run's line coverage is reported with
it, along with the run's Git history. Once every job that measures the
commit's coverage has finished, tell Tuist the commit's coverage is complete
with `mix tuist.coverage.complete`; until then the commit is shown as in
progress and stays out of the branch's coverage trend.

### Without shards

Run the whole suite with coverage, then mark the commit complete:

```sh
mix tuist.test --cover
mix tuist.coverage.complete
```

Tuist reads the counters Erlang's `cover` collected once the suite finishes,
so your coverage tool keeps working as before: `mix test`'s HTML report and
threshold, or excoveralls.

### With shards

Build the shards with `--cover`, run each one with `--cover`, and mark the
commit complete from a job that runs after all of them:

```sh
# once, on the machine that builds
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-total 4 --cover

# on each shard
TUIST_SHARD_INDEX=0 mix tuist.test --cover

# once every shard has finished
mix tuist.coverage.complete
```

On GitHub Actions, for example:

```yaml
permissions:
  contents: read
  id-token: write # the tasks sign in with GitHub's identity token
jobs:
  build:
    outputs:
      matrix: ${{ steps.plan.outputs.matrix }}
    steps:
      # checkout, Elixir, mix deps.get
      - run: MIX_ENV=test mix compile --warnings-as-errors
      - id: plan
        run: MIX_ENV=test mix tuist.test.build --shard-total 4 --cover
  test:
    needs: build
    strategy:
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      # checkout, Elixir, mix deps.get
      - run: mix tuist.test --cover
  complete:
    needs: test
    # A shard with a failing test still reported its coverage.
    if: ${{ !cancelled() }}
    steps:
      # checkout, Elixir, mix deps.get
      - run: mix tuist.coverage.complete
```

Each shard reports its share and Tuist merges them into one run. Erlang's
`cover` compiles every module of the project again at the start of each run,
which on a large project costs every shard a minute or more, so with `--cover`
the build's modules are recompiled once, on the machine that builds, with the
runtime's native line counters. Each shard switches the counters on and counts
with them instead of running Mix's coverage tool, so no Mix coverage report is
written. Only the modules Mimic copies are compiled for `cover`, because Mimic
keeps a `cover` compiled module's counts across the swaps it makes and
reloading a module resets its native counters.

A shard on a runtime without the JIT cannot count natively and uses Mix's
coverage tool, as does one built without `--cover`. Its coverage is then
exported, under `cover/shard-<index>` unless you pass `--export-coverage`
yourself, rather than held to the project's threshold, which a shard running
part of the suite would not meet.

### What is reported

Each covered file is reported with the OTP application it belongs to and the
Git blob it had, and files under your test paths count as test code, which no
figure includes. Each file also lists its functions; lines that hold only code
the compiler or a macro generates, such as the line `defmodule`, `schema` or
`use` sits on, count for the file but belong to no function.

A run that picks its tests (`--only`, `--exclude`, `--failed`, `--stale`, or
test files on the command line) is reported as partial and stays out of the
branch's coverage trend.

The run's Git history is the merge base with the branch a pull request merges
into and the commits Tuist does not have yet. A shallow
clone is deepened, within a time budget, until the merge base is found.

## Optional reported actor

Build and test reports include an optional `x-tuist-actor-id` header only when explicitly configured. No claim is sent by default, and operating-system usernames are not detected. This is an unverified label, not a credential or a verified user identity. Existing authentication and report payloads are unchanged. Older servers ignore the header; displaying the claim requires server support.

Use `TUIST_ACTOR_ID=employee-123`, a runtime `actor_id: "employee-123"` option, or `tuist: [actor_id: "employee-123"]` in your Mix project to opt in, in that order. Values must be 1–128 bytes of printable, non-space ASCII. An explicitly empty or invalid override omits the claim instead of falling back to a lower-precedence setting.

Set `TUIST_ACTOR_ID=""` to suppress a configured claim, including when a custom proxy rejects unfamiliar headers. Claims may be visible to report viewers on supporting servers; avoid sensitive personal identifiers.

## Tag runs with custom metadata

Every submitted run can carry customer-supplied tags (labels for filtering)
and values (key/value pairs). Sources merge with the environment last:

```elixir
def project do
  [
    app: :my_app,
    tuist: [
      url: "https://tuist.example.com",
      project: "your-account/your-project",
      tags: ["nightly"],
      values: %{"team" => "platform"}
    ]
  ]
end
```

`TUIST_TAGS` (comma-separated) and `TUIST_VALUES` (`key=value` pairs,
comma-separated) override the mix.exs config. The Tuist dashboards use
those labels to group and filter runs across ecosystems.

## Compile with analytics

```sh
mix tuist.compile
mix tuist.compile --force
```

`mix tuist.compile` wraps `mix compile`, attaches an after-compiler hook to
the Elixir and `.app` compilers, and submits a build record to your Tuist
dashboard when the compile finishes. The record carries duration and status,
each warning and error as a distinct diagnostic (file, module, message,
line, and column), a per-file profile (when each file started compiling, how
long it compiled, the project files it depends on and how strongly, and how
long it sat paused waiting on other files) and the other
work the compiler reports (type checking each module, writing modules to
disk, the other Mix compilers), which together feed the build's timeline, machine samples taken once a second (processor, memory,
network and disk throughput), plus the same environment metadata (Elixir and
[Open Telecom Platform](https://www.erlang.org/doc/system/otp) versions, Mix
environment, git ref, and continuous integration provider) that
`mix tuist.test` submits. Every argument other than `--url` and `--project`
is forwarded to `mix compile`. Submission failures never change the exit code
of `mix compile`.

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
The package currently has focused authentication and locking tests.

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
