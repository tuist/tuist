---
{
  "title": "Elixir project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Set up Tuist once for Elixir dependency caching, build and test insights, flaky test detection, and optional test sharding."
}
---
# Elixir project {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Set up Tuist once, then keep using `mix compile` and `mix test`. The `tuist_ex` Hex package caches supported dependencies and reports builds and test runs to your dashboard.

## Prerequisites

- An Elixir project built with Mix, on Elixir 1.18 or later.
- A Tuist account.

## Set up Tuist {#set-up-tuist}

Create a project in the Tuist dashboard and choose **Mix (Elixir)** as its build system. Add the package to the dependencies in your `mix.exs`:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Fetch it, configure your project, and log in:

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

Setup updates `mix.exs` with your project handle, enables dependency caching, and installs the compile and test aliases. It preserves other settings and standard test preparation such as Phoenix's database setup. If it cannot safely integrate a custom alias, it stops without changing the file.

Commit the updated `mix.exs` so your team and CI use the same setup. No scripts or evaluation code to copy. Login opens a browser; see <.localized_link href="/guides/install-hex-package#authenticate">authentication</.localized_link> for headless login and CI credentials.

Now run your usual commands:

```bash
mix compile
mix test
```

Builds appear under **Builds**, test runs under **Tests**, and dependency cache activity under **Mix cache**. This is the shared setup for all three. Flaky test detection uses the reported runs; retries and CI sharding are optional.

## Dependency caching

Tuist automatically selects supported Hex and Git dependencies, without a dependency list. A cache miss compiles normally and saves the result; a hit restores it. Native/custom compilation and local dependencies remain with Mix.

Compilation must be reproducible: declare extra compile-time inputs and exclude dependencies with unmodeled inputs or required side effects. See <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link> for supported inputs, cache verification, and customization.

## Build insights

Build times, the dependency graph between your files, and how both evolve over time give you what you need to optimize your build graph and make the most of all the cores available in the environment where the compilation takes place.

With the `compile` alias in place, Tuist reports every build: how long it took, its warnings and errors, how long each file took to compile, and the files it depends on. Open **Builds** on the dashboard after your next `mix compile` to see it.

## Test insights

Tuist records the result and the duration of every test in every `mix test` run, so you can see how your test suite evolves over time, find the tests that are slow or got slower, and understand why a run failed in CI. You'll find them under **Tests** on the dashboard, down to the module, the `describe` block, and the test.

## Flaky tests

A flaky test passes and fails with the same code. Tuist marks a test as flaky when it failed and passed on the same commit in CI. You can also have the package retry the tests that failed, which detects them in a single run:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

A test that passes on a retry is reported as flaky and the run succeeds. The **Flaky Tests** page lists them.

## Test sharding

Test sharding distributes your test suite across CI runners. Tuist balances the shards using how long each test file took in earlier runs, and it compiles the project once and shares that build with every runner. One command plans the shards:

```bash
mix tuist.test.build --shard-max 4
```

Each runner then runs its share with `TUIST_SHARD_INDEX` set, and the results arrive on the dashboard as a single test run:

```bash
TUIST_SHARD_INDEX=0 mix test
```

## Bring the team along

Insights compound with the number of people connected to the project. Invite your teammates to the organization from the account settings on the dashboard, and set up <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) so onboarding is a click rather than a per-person `mix tuist.login`.

For CI, don't use a personal login. GitHub Actions, CircleCI, and Bitrise can authenticate through OpenID Connect; on other providers, set a scoped `TUIST_TOKEN`. Follow the <.localized_link href="/guides/install-hex-package#authenticate">CI authentication steps</.localized_link>.
