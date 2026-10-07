---
{
  "title": "Elixir Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute the tests of your Elixir project across multiple CI runners with Tuist Test Sharding."
}
---
# Elixir test sharding {#elixir-test-sharding}

The Tuist Hex package includes built-in support for sharding the tests of an Elixir project. It uses the Tuist server to create balanced shard plans based on historical timing data, and it compiles your project once so every runner can go straight to running tests.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/elixir">Test insights</.localized_link> must be configured

## How it works {#how-it-works}

Test sharding follows a two-phase workflow:

1. **Build phase:** Tuist compiles your project for testing, enumerates your test files, and creates a **shard plan** on the server. The server uses historical test timing data from the last 30 days to distribute tests across shards so each shard takes roughly the same amount of time. The build phase uploads the build and outputs a **shard matrix** that your CI system uses to spawn parallel runners.
2. **Test phase:** Each CI runner receives a **shard index**, downloads the build, and executes only the tests assigned to that shard.

Tests are distributed by file: every test in a file runs on the same shard. Tests that Tuist has not seen yet get an estimate, so the first plans of a project are less balanced than later ones.

## Build phase {#build-phase}

Prepare test shards using the `tuist.test.build` task:

```sh
mix tuist.test.build --shard-max 5
```

This task:
1. Compiles the project in the test environment
2. Creates a shard plan on the Tuist server using historical timing data
3. Uploads the build so the shards don't compile again
4. Outputs a shard matrix for your CI system

### Build options {#build-options}

| Option | Description |
|--------|-------------|
| `--shard-max <N>` | Maximum number of shards (default: 2) |
| `--shard-min <N>` | Minimum number of shards |
| `--shard-total <N>` | Exact number of shards, instead of a range |
| `--shard-max-duration <MS>` | Target maximum duration per shard in milliseconds |
| `--shard-reference <REF>` | The name the shards find the plan by |
| `--no-upload` | Plan the shards without uploading the build; each shard then compiles for itself |

Every other argument is forwarded to `mix compile`.

The shard reference is automatically derived from CI environment variables (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, `CIRCLE_WORKFLOW_ID`, `BUILDKITE_BUILD_ID`) or can be set explicitly via the `TUIST_SHARD_REFERENCE` environment variable. Outside those providers you have to set it, to a value that the build phase and the shards of one pipeline run share. On GitHub Actions, references also include the run attempt: when rerunning only failed jobs, pass the original build job's reference rather than deriving a new one in the shard jobs.

## Test phase {#test-phase}

Each shard runner executes its assigned tests using `mix tuist.test`, or `mix test` if you <.localized_link href="/guides/install-hex-package#aliases">aliased it</.localized_link>. When `TUIST_SHARD_INDEX` is set, the package fetches the shard assignment from the server, downloads the build, and runs only the assigned test files without compiling.

```sh
TUIST_SHARD_INDEX=0 mix test
```

Any test files or directories you pass narrow the shard further: only the files that are both in the shard and in your selection run. A shard that ends up with no tests exits successfully.

The results of all the shards arrive on the dashboard as a single test run, and its **Shards** section shows how long each one took.

If setup must run before the tests, download the build first without starting the application:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex + tuist.test --prepare-only
```

Run your setup in a separate process, then execute the shard without downloading the build again:

```sh
TUIST_SHARD_INDEX=0 mix tuist.test --no-download
```

Both commands need the same shard reference. `--prepare-only` requires an uploaded build, and `--no-download` fails if the prepared application artifact is missing. Keeping database migrations in a separate process also avoids module-redefinition warnings when migration regression tests load those modules themselves.

When testing different environments, pass a stable `--scheme` label, such as `--scheme clickhouse-current` or `--scheme clickhouse-floor`. Results with different labels are not treated as flaky reruns of the same configuration.

### What the shards need {#what-the-shards-need}

The uploaded build is the `_build/test` directory. Each shard runner still needs:
- The same checkout as the build phase
- The same Elixir and Erlang/OTP versions
- The dependency sources, from `mix deps.get`

Sharding from the root of an umbrella project is not supported yet. Run both phases inside one of its applications.

## Continuous integration {#continuous-integration}

### GitHub Actions {#github-actions}

On GitHub Actions the build phase writes the shard indexes to the `matrix` output of its step. Use a matrix strategy to run shards in parallel:

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - id: build
        run: mix tuist.test.build --shard-max 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix tuist.test
```

### Other providers {#other-providers}

Outside GitHub Actions the build phase writes the plan to `.tuist-shard-matrix.json`:

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

Use `shard_count` to set up your parallel jobs, and give each job its `TUIST_SHARD_INDEX`, from `0` to `shard_count - 1`. On a provider that Tuist does not derive the reference from, also give every job the same `TUIST_SHARD_REFERENCE`.
