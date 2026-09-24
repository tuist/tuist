# Tuist for Elixir

This package provides `mix tuist.login` for authentication and `mix tuist.test`
for ExUnit analytics, both writing to the same Tuist server the command line
tool and Gradle plugin use. Compile analytics land in a separate follow-up
package release.

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
mix tuist.test -- --trace     # forwards --trace to mix test
```

`mix tuist.test` installs an ExUnit formatter alongside the default one and
runs `mix test`. When the suite finishes, it POSTs a summary of the run,
each module, each suite (from `describe` blocks), and each test case,
including failure messages and source locations, to the Tuist server. Test
timings are converted from microseconds to milliseconds. Everything after
`--` is forwarded to `mix test` verbatim.

Elixir, [OTP](https://www.erlang.org/doc/system/otp), `Mix` environment, the
current git ref, and any recognised continuous integration provider metadata
travel with the payload so a dashboard can group runs by branch, commit, and
CI run.

Analytics submission never changes the exit code of `mix test`. If a request
fails, set `TUIST_DEBUG=1` to print the reason to standard error. Authentication
reuses the credentials from `mix tuist.login`, or the `TUIST_TOKEN` environment
variable if set.

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
