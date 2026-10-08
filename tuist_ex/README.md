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
reuses the credentials from `mix tuist.login`, or the `TUIST_TOKEN` environment
variable if set.

## Keep using `mix test` and `mix compile`

The Tuist tasks take the same command line as the tasks they wrap, so you can
alias them once and nobody, person or coding agent, has to learn a different
command:

```elixir
def project do
  [
    app: :my_app,
    aliases: [test: "tuist.test", compile: "tuist.compile"],
    tuist: [project: "your-account/your-project"]
  ]
end
```

`mix test test/my_test.exs:12 --trace` then runs and reports exactly as
`mix tuist.test` would. The alias also gets the environment right: Mix runs
`mix test` in the test environment, whereas a task typed as `mix tuist.test`
starts in `dev` and has to start over in a new process. If you call the tasks
by name, set `MIX_ENV=test` or add
`preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]` to
`def cli` in your `mix.exs`. Aliasing `compile` covers every compile, including
the ones `mix test` or `mix phx.server` trigger; a compile that finds nothing
to do is not reported.

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
mix tuist.test.build --shard-max 4
```

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

Pass `--cover` and the run's line coverage is reported with it:

```sh
mix tuist.test --cover
```

Tuist reads the counters Erlang's `cover` collected once the suite finishes,
so your coverage tool keeps working as before: `mix test`'s HTML report and
threshold, or excoveralls. Each covered file is reported with the OTP
application it belongs to and the Git blob it had, and files under your test
paths count as test code, which no figure includes. A run that picks its tests
(`--only`, `--exclude`, `--failed`, `--stale`, or test files on the command
line) is reported as partial and stays out of the branch's coverage trend.
Shards each report their share and Tuist merges them.

With coverage, the run also reports its Git history: the merge base with the
branch a pull request merges into, the files it changed, and the commits Tuist
does not have yet. A shallow clone is deepened, within a time budget, until
the merge base is found. Once every job of the pipeline that measures coverage
has finished, tell Tuist the commit's coverage is complete:

```sh
mix tuist.coverage.complete
```

Until then the commit is shown as in progress and stays out of the trend.

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
