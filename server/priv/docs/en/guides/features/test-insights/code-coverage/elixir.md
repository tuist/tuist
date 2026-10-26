---
{
  "title": "Elixir Code Coverage",
  "titleTemplate": ":title · Code Coverage · Test Insights · Features · Guides · Tuist",
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

The package uploads the coverage along with the run's test results. It also prints Mix's per-module summary when the suite finishes, and fails the run with exit status 3 when the total falls below the threshold your project sets:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

The threshold is 90% unless you set one, as with Mix's own coverage tool, and `summary: false` turns off both the summary and the threshold. Modules listed in `test_coverage: [ignore_modules: [...]]` are left out of the summary and the upload.

Coverage relies on the <.localized_link href="/guides/features/test-insights/elixir#git-history">Git history</.localized_link> the package uploads, which places the commit on its branch. Runs on continuous integration always upload it, and `--cover` runs upload it on any machine. With `--cover`, the package also finds where a pull request branched off: it fetches the base branch and deepens a shallow clone as far as it needs. Set `TUIST_GIT_UNSHALLOW_ENABLED=false` to keep it from contacting the remote.

### Sharded runs {#sharded-runs}

When you <.localized_link href="/guides/features/test-sharding/elixir">shard your tests</.localized_link>, add `--cover` to the build phase's `mix tuist.test.build` command, so the build every shard downloads already carries the coverage counters:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Then run each shard with `--cover`. A shard reports only its own coverage and doesn't check the threshold, since it runs part of the suite. Tuist merges the shards of a run into one figure.

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

We measured native counting against Mix's coverage tool on Livebook and on generated projects of increasing size, on a 12-core Linux machine. These are those projects' numbers, not guarantees. Times are added to a run without coverage:

| Project | Mix's coverage tool | First native run | Later native runs |
| --- | --- | --- | --- |
| Livebook (about 20,000 executable lines) | +6.3 s | +5.4 s | +0.4 s |
| Generated, about 35,000 executable lines | +3 s | +2 s | |
| Generated, about 140,000 executable lines | +31 s | +7 s | |
| Generated, about 560,000 executable lines | +713 s | +30 s | |

A first run recompiles the modules with the counters; later runs only recompile what changed. Mix's coverage tool reads its counters in time that grows faster than the number of executed lines, so the gap widens on larger projects.

## Limitations {#limitations}

- **No HTML report.** Counting natively writes no report to the `test_coverage: [output: ...]` directory, and the run warns when one is set. The dashboard's file pages show the covered lines instead.
- **Retries don't add coverage.** With <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link>, the coverage is the first run's; the retries of failed tests don't carry `--cover`.
- **Signed runs only.** Coverage is uploaded only by runs that authenticate with Tuist. A run published without credentials to a self-hosted server sends its test results without coverage or Git history.

## Querying coverage {#querying}

The dashboard's **Code Coverage** page shows each commit's figure, its applications and its files, with the lines each run covered. The same data is available to agents through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>.
