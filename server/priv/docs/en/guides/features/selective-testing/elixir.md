---
{
  "title": "Elixir selective testing",
  "titleTemplate": ":title · Selective Testing · Features · Guides · Tuist",
  "description": "Run only the ExUnit tests your change can affect, using the code coverage of earlier runs, with the Tuist Hex package."
}
---
# Elixir selective testing {#elixir-selective-testing}

> [!NOTE]
> **Early access**
>
> Coverage-based test selection is in early access. Contact us to enable it for your account. Until it's enabled, every test runs.

The Tuist Hex package can skip the ExUnit tests your change can't affect. Each test run records which lines each test executed. On a later commit, Tuist compares the files your change touched with that coverage and leaves out the tests that executed none of them.

> [!IMPORTANT]
> **Requirements**
>
> - Complete the <.localized_link href="/guides/get-started/elixir-project">shared Elixir setup</.localized_link>, so `mix test` runs through `mix tuist.test`
> - Run your CI tests with `--cover`, which records the coverage Tuist selects by

## Enabling it {#enabling-it}

Set the coverage strategy in your `mix.exs`:

```elixir
def project do
  [
    app: :my_app,
    tuist: [
      project: "{account-handle}/{project-handle}",
      selective_testing: [strategy: :coverage]
    ]
  ]
end
```

Then run your tests with coverage on CI:

```bash
mix test --cover
```

A run without `--cover`, such as a local `mix test`, runs every test.

## Full test runs {#full-test-runs}

A selective run compares your commit with a recent run in its history that executed every test, its baseline. Run every test with `--no-selective-testing`, for example on every commit of your default branch:

```bash
mix test --cover --no-selective-testing
```

Without a recent full run, coverage isn't applied and every test runs. We recommend the default branch: a full run there also catches, before a change ships, what coverage can't see, such as a fixture or a service a test depends on.

## What runs {#what-runs}

With the strategy on, `mix tuist.test` asks Tuist which tests your change can affect before the suite starts, and prints what it decided:

```text
Tuist: coverage-based test selection: 3 of 5 tests selected, 2 skipped
  Nothing selected in 1 module: CartTest
```

Skipped tests are excluded from the run, so ExUnit reports them as excluded. Tuist leaves out exactly the tests it skips, so a test with the same name in another module still runs. A test you pick with `--only`, `--include` or `file:line` runs even when Tuist would skip it. Some tests always run:

- **New tests**, and every test in a test file your change touched.
- **Tests in `async: true` modules.** ExUnit runs them at the same time as other tests, so Tuist can't tell which code each one executed. A module that tests widely used code selects better when it isn't async.
- **Tests that failed last time**, and tests without recorded coverage.
- **Every test, when your change touches a file Tuist can't attribute to tests**, such as a module no test executed at runtime (new modules, modules only used at compile time) or a file under `priv`.

Tests skipped with `@tag :skip`, excluded by your test helper, or quarantined in Tuist stay as they are.

Sometimes coverage isn't applied, and the output says why: every test runs. That happens without a recent full run, when the change touches more than 5,000 files, or when it changes a file that can affect any test: `mix.exs`, `mix.lock`, anything under `config/`, `test_helper.exs`, or a toolchain file such as `.tool-versions`. If Tuist can't be reached, every test runs, with a warning.

> [!WARNING]
> **Compile-time dependencies**
>
> Coverage records the code tests execute at runtime. A macro runs when its callers compile, so a test can depend on a changed macro without executing its file. The full runs on your default branch catch what that misses.

## Sharding {#sharding}

<.localized_link href="/guides/features/test-sharding/elixir">Test sharding</.localized_link> selects once, in the build job, and plans only the test files with selected tests. Each shard then leaves out the skipped tests of its files:

```bash
mix tuist.test.build --shard-max 4
```

Pass `--no-selective-testing` to `mix tuist.test.build` to plan every test file.

## Turning it off {#turning-it-off}

Pass `--no-selective-testing` to run every test, or remove `selective_testing` from your `mix.exs`.
