---
{
  "title": "Elixir Code Coverage",
  "titleTemplate": ":title · Code Coverage · Features · Guides · Tuist",
  "description": "Upload the line coverage of your Elixir project with mix test --cover and follow it per file, per application and per commit."
}
---
# Elixir code coverage {#elixir-code-coverage}

> [!NOTE] EARLY ACCESS
> Code coverage is in early access. [Reach out](mailto:contact@tuist.dev) to turn it on for your account. The Hex package needs no extra setting: once it's on, `--cover` runs upload their coverage.

Code coverage tells you which lines of your code your tests executed. The Hex package uploads the line coverage of every `mix test --cover` run, and Tuist folds the runs of a commit into one figure, for the project, each OTP application and each file. The dashboard's **Code Coverage** page shows it per commit and as a trend for each branch.

> [!IMPORTANT] REQUIREMENTS
> - Complete the <.localized_link href="/guides/get-started/elixir-project">shared Elixir setup</.localized_link>, which routes `mix test` through the package

## Setup {#setup}

### Run your tests with coverage {#run-your-tests}

Pass `--cover`, as you would to `mix test` without Tuist:

```sh
mix test --cover
```

The package uploads the coverage along with the run's test results. When the suite finishes, it also does what Mix's coverage tool does, configured with the same `test_coverage` options:

- **Summary.** It prints the coverage of each module and the total. `summary: false` turns it off.
- **Threshold.** It fails the run with exit status 3 when the total falls below the threshold, which is 90% unless you set one:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

As in Mix, the threshold belongs to the summary, so `summary: false` turns off both. To print the summary without failing the run, set `threshold: 0`. Modules listed in `test_coverage: [ignore_modules: [...]]` are left out of the summary and the upload.

Tuist tracks coverage per commit, so it needs your project in a Git repository: a run outside one uploads its test results but no coverage.

Coverage relies on the <.localized_link href="/guides/features/test-insights/elixir#git-history">Git history</.localized_link> the package uploads, which places the commit on its branch. Runs on continuous integration always upload it, and `--cover` runs upload it on any machine. With `--cover`, the package also finds where a pull request branched off: it fetches the base branch and deepens a shallow clone as far as it needs. Set `TUIST_GIT_UNSHALLOW_ENABLED=false` to keep it from contacting the remote.

### Sharded runs {#sharded-runs}

When you <.localized_link href="/guides/features/test-sharding/elixir">shard your tests</.localized_link>, run each shard with `--cover`:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

On a fresh runner, use the bootstrap command from the sharding guide's <.localized_link href="/guides/features/test-sharding/elixir#test-phase">test phase</.localized_link>, which keeps Mix from compiling every dependency before the shard downloads its build, and add `--cover` to it.

A shard reports only its own coverage and doesn't check the threshold, since it runs part of the suite. Tuist merges the shards of a run into one figure.

Each shard adds the coverage counters to the build it downloads. To do it once instead, pass `--cover` to the build phase too:

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Leave it off when you keep the build directory between pipeline runs and reuse it in runs that don't collect coverage, so that build stays without counters.

### Complete each commit on CI {#complete-each-commit}

A commit's coverage often comes from several jobs: one per shard, per database version, or per application. Tuist can't tell when the last of them has reported, so tell it. Once every test job for a commit has finished, run this in a job that depends on all of them:

```sh
MIX_ENV=test mix tuist.coverage.complete
```

The task reads the commit from `GIT_COMMIT` or the checkout's `HEAD`; pass `--commit <sha>` to name another one. Until a commit is complete, its coverage shows as **In progress** and stays out of its branch's trend.

## How it works {#how-it-works}

### Native line counters {#native-line-counters}

Mix's coverage tool compiles every module again for Erlang's `cover` at the start of each run, which gets slow on large projects. The package counts with the runtime's native line counters instead. It recompiles only the modules a compile wrote since the last run, switches the runtime to those counters, and reads them when the suite finishes. Mix's coverage tool is left out, but its summary and threshold are kept.

The package falls back to Mix's coverage tool, with the same upload, for:

- The root of an umbrella project. Run the tests inside each application to count natively.
- A project that sets its own `test_coverage: [tool: ...]`.
- A runtime without the JIT, which can't count natively.

### What Tuist measures {#what-tuist-measures}

- **Applications.** Each OTP application is a target on the dashboard, with its own coverage.
- **Product code only.** Files under your test paths are test code. Tuist stores them but leaves them out of every figure.
- **Lines per file.** A line counts once per file, however many modules it belongs to.
- **Functions.** Each line belongs to the function whose clause starts closest above it. Functions the compiler or a macro generates, such as `__info__/1` or `__schema__/1`, aren't listed, but their lines still count for their file.

So Tuist's figures differ from Mix's own coverage report in a few ways: they leave test code out and count lines per file rather than per module. Native counting also sees the code that runs while your application starts, and leaves out the lines the compiler proves can never run, which Mix's tool reports as never covered.

### Skipped tests {#skipped-tests}

Tuist can't carry forward the coverage of tests a run leaves out: the package records what the whole run executed, not what each test executed. So when a run's own arguments leave tests out, with `--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures`, or test files or lines, the commit's coverage is **Incomplete**, unless a run of the same variant that left nothing out ran too. Two runs that each leave tests out, such as `--exclude slow` and `--only slow`, still make the commit incomplete, even though together they ran every test.

Some tests are left out on purpose and don't make a commit incomplete:

- **Your test helper's exclusions.** Tests that `ExUnit.start(exclude: [...])` leaves out by default are your project's choice of what its suite runs by default, so Tuist doesn't count them as missing. Run them in another job, with `--include` or `--only`, to add their coverage to the commit.
- **Tests skipped in code** with `@tag :skip`.
- **Tests that <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">quarantine</.localized_link> skips.** They're left out as if they had been removed, so the lines only they covered count as uncovered.

### Complete and incomplete commits {#commit-status}

Each commit on the dashboard has a status:

| Status | Meaning |
| --- | --- |
| In progress | Runs have reported coverage, but `mix tuist.coverage.complete` hasn't run for the commit yet. |
| Complete | Every test of the commit's runs ran, or was left out on purpose. |
| Incomplete | Some coverage couldn't be determined, so the figure is a lower bound. |
| Not measured | No run reported coverage for the commit. |

A branch's trend only includes complete commits. A commit is incomplete when, for example:

- Every run of a variant left tests out with its own arguments.
- Every run of a variant was missing some of its shards.
- A variant's coverage only came from CI runs on a checkout with uncommitted changes.

A variant is the label you pass with `--scheme`, such as a database version. Runs without a label are one variant. The commit's figure merges every run, but Tuist checks each variant for completeness on its own, so each variant needs a run that leaves nothing out.

## Performance impact {#performance-impact}

Collecting coverage adds overhead, so runs with `--cover` take longer than runs without it. The first run recompiles your modules with the line counters; later runs only recompile what changed, so they cost much less. On large projects, native counting is also much faster than Mix's coverage tool.

## Limitations {#limitations}

- **No HTML report.** Counting natively writes no report to the `test_coverage: [output: ...]` directory, and the run warns when one is set. The dashboard's file pages show the covered lines instead.
- **Retries don't add coverage.** With <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link>, the coverage is the first attempt's. That attempt already ran the failed tests, so the only lines missing are those a flaky test reaches on a retry but not on its first attempt.
- **No coverage from pull requests from forks.** Coverage is uploaded only by runs that authenticate with Tuist, and CI usually withholds secrets and identity tokens from pull requests opened from forks, so those runs report no coverage. Once merged, the commit runs on your branch with credentials and reports its coverage as usual.

## Querying coverage {#querying}

The dashboard's **Code Coverage** page shows each commit's figure, its applications and its files, with the lines each run covered. The same data is available to agents through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>.
