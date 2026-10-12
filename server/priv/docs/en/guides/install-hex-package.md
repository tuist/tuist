---
{
  "title": "Install the Hex package",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Hex package in your Elixir project."
}
---
# Install the Hex package {#install-the-hex-package}

Tuist provides a [Hex](https://hex.pm/packages/tuist_ex) package, `tuist_ex`, that integrates with your Elixir project to enable features like <.localized_link href="/guides/features/build-insights/elixir">build insights</.localized_link> and <.localized_link href="/guides/features/test-insights/elixir">test insights</.localized_link>. This guide walks you through installing and configuring it.

The package requires Elixir 1.18 or later. It does not need the Tuist command-line interface.

## 1. Create the project {#create-the-project}

Create a project in the Tuist dashboard and choose **Mix (Elixir)** as its build system. Its handle, `account/project`, is what connects your Mix project to it.

## 2. Add the package {#add-the-package}

Add `tuist_ex` to the dependencies in your `mix.exs` and set the project handle:

```elixir
def project do
  [
    app: :my_app,
    deps: deps(),
    tuist: [project: "account/project"]
  ]
end

defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Then fetch it:

```bash
mix deps.get
```

The package only adds Mix tasks, so `runtime: false` keeps it out of your running application.

## 3. Authenticate your team and continuous integration {#authenticate}

Each teammate runs the following to get access to the Tuist features on their machine:

```bash
mix tuist.login
```

It opens a browser and waits for you to authorize. To log in without a browser, pass your credentials:

```bash
mix tuist.login --email person@example.com --password secret
```

When you use a self-hosted or local Tuist server, set its base URL in `mix.exs`, or pass it with `--url`:

```bash
mix tuist.login --url http://localhost:8080
```

Keep the hostname spelling consistent. For example, a login stored for `localhost` is separate from one stored for `127.0.0.1`.

On GitHub Actions, CircleCI, and Bitrise, continuous integration needs no login step. The first time a task sends a report, it exchanges the provider's OpenID Connect token for a Tuist token. <.localized_link href="/guides/integrations/gitforge/github">Connect your GitHub repository</.localized_link> to your Tuist project, and on GitHub Actions give the job the `id-token: write` permission:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix tuist.test
```

Pull requests from forks don't get an OpenID Connect token, so their runs aren't reported and still pass or fail as usual. On other providers, set the `TUIST_TOKEN` environment variable to an account token. Follow the <.localized_link href="/guides/integrations/continuous-integration#authentication">continuous integration authentication guide</.localized_link> to create one.

## 4. Keep using `mix test` and `mix compile` {#aliases}

The package adds `mix tuist.test` and `mix tuist.compile`, which run `mix test` and `mix compile` and report the result. Both take the same command line as the task they wrap, so you can alias them and nobody, person or coding agent, has to learn a different command:

```elixir
def project do
  [
    app: :my_app,
    aliases: [test: "tuist.test", compile: "tuist.compile"],
    tuist: [project: "account/project"]
  ]
end
```

`mix test test/my_app_test.exs:12 --trace` then runs and reports exactly as `mix tuist.test` would. Aliasing `compile` covers every compile, including the ones `mix test` or `mix phx.server` trigger. A compile that finds nothing to do is not reported.

The tasks also work when you call them by their own name. Mix starts a task typed that way in the `dev` environment, so the task has to start over in a second process for the test environment. Add the tasks to the preferred environments to skip that:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## Configuration reference {#configuration-reference}

The following options are available under `tuist` in the project options of `mix.exs`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `project` | `String` | none (required) | The project identifier in `account/project` format. |
| `url` | `String` | `"https://tuist.dev"` | The base URL of the Tuist server. |
| `test_retries` | `integer` | `0` | How many times to retry the tests that failed; see <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link>. |
| `tags` | list of `String` | `[]` | Tags to attach to every build; see <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">custom metadata</.localized_link>. |
| `values` | map | `%{}` | Key-value data to attach to every build. |

Environment variables take precedence over `mix.exs`:

| Variable | Description |
| --- | --- |
| `TUIST_PROJECT` | The project identifier in `account/project` format. |
| `TUIST_URL` | The base URL of the Tuist server. |
| `TUIST_TOKEN` | The token to authenticate with, instead of the stored login. |
| `TUIST_TEST_RETRIES` | How many times to retry the tests that failed. |
| `TUIST_TAGS` | Comma-separated tags to attach to the build. |
| `TUIST_VALUES` | Comma-separated `key=value` pairs to attach to the build. |
| `TUIST_DEBUG` | Set to `1` to print why a report could not be sent. |

Reporting never changes the exit code of `mix test` or `mix compile`. If a report cannot be sent, the task says nothing unless `TUIST_DEBUG=1` is set.

## Next steps {#next-steps}

Once the package is installed and configured, you can use:

- <.localized_link href="/guides/features/build-insights/elixir">Build insights</.localized_link> to track compile times, warnings, and what holds your builds back.
- <.localized_link href="/guides/features/test-insights/elixir">Test insights</.localized_link> to track test performance down to each test.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Flaky tests</.localized_link> to detect and track tests that fail intermittently.
- <.localized_link href="/guides/features/test-sharding/elixir">Test sharding</.localized_link> to split your tests across continuous integration runners.
