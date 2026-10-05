---
{
  "title": "Elixir project",
  "titleTemplate": ":title · Get started · Guides · Tuist",
  "description": "Connect an Elixir project built with Mix to Tuist for build and test insights across CI, flaky test detection, and test sharding."
}
---
# Elixir project {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Follow this path to point an existing Elixir project at Tuist. The `tuist_ex` Hex package reports your builds and test runs to the dashboard, and once you alias its tasks you keep typing `mix test` and `mix compile`.

## Prerequisites

- An Elixir project built with Mix, on Elixir 1.18 or later.
- A Tuist account.

## Connect the project

Create a project in the Tuist dashboard and choose **Mix (Elixir)** as its build system. Then add the package to your `mix.exs`, with the project's handle:

```elixir
def project do
  [
    app: :my_app,
    deps: deps(),
    aliases: [test: "tuist.test", compile: "tuist.compile"],
    tuist: [project: "account/project"]
  ]
end

defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Fetch it and log in. The login opens a browser and waits for you to authorize:

```bash
mix deps.get
mix tuist.login
```

If you're driving this from a coding agent or a script, pass your credentials instead:

```bash
mix tuist.login --email person@example.com --password secret
```

Sanity-check with `mix test`. It should run as it always has, and the run should appear under **Tests** on the dashboard.

Everything below is optional and independent.

## Build insights

Build times, the dependency graph between your files, and how both evolve over time give you what you need to optimize your build graph and make the most of all the cores available in the environment where the compilation takes place.

With the `compile` alias in place, Tuist reports every build: how long it took, its warnings and errors, how long each file took to compile, and the files it depends on. Open **Builds** on the dashboard after your next `mix compile` to see it.

## Test insights

Tuist records the result and the duration of every test in every `mix test` run, so you can see how your test suite evolves over time, find the tests that are slow or got slower, and understand why a run failed in CI. You'll find them under **Tests** on the dashboard, down to the module, the `describe` block, and the test.

## Flaky tests

A flaky test passes and fails with the same code. Tuist marks a test as flaky when it failed and passed on the same commit in CI. You can also have the package retry the tests that failed, which detects them in a single run:

```elixir
tuist: [project: "account/project", test_retries: 2]
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

For CI, don't use a personal login. Set `TUIST_TOKEN` scoped to your project (create it from the project settings on the dashboard).
