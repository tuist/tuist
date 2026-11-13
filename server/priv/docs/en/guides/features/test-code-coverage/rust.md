---
{
  "title": "Rust Code Coverage",
  "titleTemplate": ":title · Code Coverage · Features · Guides · Tuist",
  "description": "Upload the line coverage of your Rust project's Cargo tests and follow it per file, per package and per commit."
}
---
# Rust code coverage {#rust-code-coverage}

Code coverage tells you which lines of your code your tests executed. Tuist measures the line coverage of every `cargo test` run with LLVM's source-based coverage and folds the runs of a commit into one figure, for the project, each package and each file. The dashboard's **Code Coverage** page shows it per commit and as a trend for each branch.

> [!IMPORTANT]
> **Requirements**
>
> - Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link>
> - The LLVM tools of your Rust toolchain (`llvm-tools`). Tuist installs them on a toolchain rustup manages.
> - Your project in a Git repository

## Setup {#setup}

### Turn coverage on {#turn-coverage-on}

Add this to the `tuist.toml` at your repository root:

```toml
[test_insights.coverage]
upload = true
```

Then run your tests as usual:

```sh
tuist cargo test --workspace
```

Tuist builds your repository's crates with `-C instrument-coverage`, runs the tests, and uploads their coverage along with the run's test results. Your tests' output and exit code don't change. To override the setting for a single run, set `TUIST_COVERAGE_UPLOAD=1` or `TUIST_COVERAGE_UPLOAD=0`.

Coverage relies on the Git history Tuist uploads with each run that collects it, which places the commit on its branch. A run outside a Git repository uploads its test results but no coverage.

### Sharded runs {#sharded-runs}

When you <.localized_link href="/guides/features/test-sharding/rust">shard your tests</.localized_link>, every shard that runs with coverage on reports the coverage of its own targets, and Tuist merges the shards of a run into one figure. A shard runs part of the suite on purpose, so it doesn't make the commit's coverage incomplete.

### Complete each commit on CI {#complete-each-commit}

A commit's coverage often comes from several jobs: one per shard or per feature set. Tuist can't tell when the last of them has reported, so tell it. Once every test job for a commit has finished, run this in a job that depends on all of them:

```sh
tuist cargo coverage-complete
```

The command reads the commit from the checkout, or the one your CI provider reports on a pull request; pass `--commit <sha>` to name another one. Until a commit is complete, its coverage shows as **In progress** and stays out of its branch's trend.

## How it works {#how-it-works}

### What Tuist measures {#what-tuist-measures}

- **Packages.** Each Cargo package is a target on the dashboard, with its own coverage.
- **Product code only.** Integration tests, benchmarks and examples (the `tests/`, `benches/` and `examples/` directories, and targets of those kinds) are test code. Tuist stores them but leaves them out of every figure. Unit tests in a `#[cfg(test)]` module are part of their source file, so their lines count with it, as in `cargo llvm-cov`.
- **Functions.** Each line belongs to the function that starts closest above it. A generic function counts once, however many types it was instantiated with.
- **Doctests** run as usual but aren't measured.

Tuist also records which code each test binary executed, for coverage-based test selection later. `cargo test` runs a binary's tests in one process, so that record belongs to the binary as a whole, not to its individual tests.

### Skipped tests {#skipped-tests}

When a run's own arguments leave tests out, such as a test name filter, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` or `--test`, the commit's coverage is **Incomplete**, unless another run of the commit that left nothing out ran too. A failure that stops `cargo test` before every test binary ran has the same effect. Add `--no-fail-fast` to keep running the remaining binaries.

Some tests are left out on purpose and don't make a commit incomplete:

- **Tests that <.localized_link href="/guides/features/test-insights/flaky-tests/rust">quarantine</.localized_link> skips.** They're left out as if they had been removed, so the lines only they covered count as uncovered.
- **The other shards' targets**, when you shard your tests.
- **Ignored tests** (`#[ignore]`), which don't run by default.

### Complete and incomplete commits {#commit-status}

Each commit on the dashboard has a status:

| Status | Meaning |
| --- | --- |
| In progress | Runs have reported coverage, but `tuist cargo coverage-complete` hasn't run for the commit yet. |
| Complete | Every test of the commit's runs ran, or was left out on purpose. |
| Incomplete | Some coverage couldn't be determined, so the figure is a lower bound. |
| Not measured | No run reported coverage for the commit. |

A branch's trend only includes complete commits.

## Performance impact {#performance-impact}

Instrumented code runs a bit slower. Tuist instruments only your repository's crates: dependencies build exactly as in your regular builds and keep coming from the cache. Tuist keeps both variants of your own crates in the target directory, so switching between runs with and without coverage doesn't rebuild them unless their code changed.

## Limitations {#limitations}

- **Custom `rustc-wrapper` with target-specific `rustflags`.** When your project sets its own `rustc-wrapper`, Tuist adds `-C instrument-coverage` to Cargo's `build.rustflags` instead. A `target.<triple>.rustflags` entry in a Cargo configuration file replaces them, so add the flag there yourself. A run whose tests wrote no coverage says so.
- **Configured target runners.** Tuist starts the test binaries through a runner of its own. A `target.<triple>.runner` in a Cargo configuration file takes its place: the run's coverage is still uploaded, but Tuist can't tell which test binary executed what. A runner set through the `CARGO_TARGET_<TRIPLE>_RUNNER` environment variable keeps working.
- **No coverage from pull requests from forks.** Coverage is uploaded only by runs that authenticate with Tuist, and CI usually withholds secrets and identity tokens from pull requests opened from forks.

## Querying coverage {#querying}

The dashboard's **Code Coverage** page shows each commit's figure, its packages and its files, with the functions each file holds. The same data is available to agents through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>.
