# Code coverage

How Tuist collects, stores and shows code coverage today. Coverage is in early access behind `Tuist.FeatureFlags.xcode_coverage_enabled?/1`.

## Scopes

Every coverage row in `coverage_files` belongs to a scope: `scope_kind` says what the row describes, and `scope_id` says which one. All build systems share the same scopes. Each build system fills in the ones it can measure.

| Scope | `scope_id` | What it holds |
| --- | --- | --- |
| `run` | empty | Everything one test run measured. Per file: the executable lines and how many times each ran, the functions, branch counters when the tool reports them, the code targets that compiled the file, and whether the file is test code. |
| `target` | the test module | Everything a test target's processes executed, from start to finish. |
| `suite` | module and suite | What ran around a suite's tests without belonging to any one of them, such as a class `setUp` or a suite's one-time setup. |
| `test` | module, suite and name | What a single test executed. |

The `run` scope is **measured coverage**. Every figure Tuist shows is computed from it, merged across a run's shards and across all the runs of a commit.

The `target`, `suite` and `test` scopes are **evidence**. They record which files, and where possible which lines, each scope executed. Unlike `run` rows, they hold no execution counts and no Git blob: the blob is read from the run's own row for the path, or from the commit's file listing. A file whose lines would exceed the report's line budget keeps only its path. No coverage total reads evidence rows directly. Their only use today is carried coverage: a run that skipped tests measures only part of the code, and the tests it skipped are carried forward from an earlier run whose evidence still applies (see [Carried coverage](#carried-coverage)).

### What the UI shows for each scope

| Scope | Shown in the UI |
| --- | --- |
| `run` | A commit's and a branch's totals and trend, the targets and files tables, and each file's page: its figures, its functions (line, covered lines, executions) and its trend. Per-line execution counts are stored, but no page shows the source line by line yet. |
| `target`, `suite`, `test` | Never shown on their own. They show up only through carried coverage: a `reported` commit's figure includes the lines carried from skipped tests, and a file's page lists them as "Covered by skipped tests, carried forward". Why a figure is `observed` (`coverage_commits.gap_reasons`) is stored but not displayed yet. |

## How the data flows

1. **Measure.** The client runs the tests with coverage on and reports the `run` scope. On Xcode, test targets that link TestCoverageAttribution also record the `target`, `suite` and `test` evidence when evidence collection is on, and Tuist lists every test the run could have executed (the enumerated tests).
2. **Ingest.** An Xcode result bundle is parsed either by the macOS xcresult processor (remote processing) or by the CLI itself (local mode, which uploads the coverage, handed to `Tests.Workers.PublishCoverageWorker`, and sends the evidence and enumeration with the run). `Tests.create_test/1` stores them: `Coverage.publish/4` the `run` rows and the run's totals in `coverage_runs`, `Coverage.Evidence.record/4` the evidence rows, and `Tests.Enumeration.record/2` the enumerated tests in `test_run_enumerated_tests`.
3. **Fold.** A few seconds after each report, `Coverage.Workers.CommitWorker` recomputes the commit (`Coverage.Commits.recompute/3`). It merges the `run` rows of the commit's clean runs and asks `Coverage.Reported.compute/3` for the commit's figure: `measured`, `reported` or `observed` (see [Figures](#figures)). The result is written to `coverage_commits`.
4. **Complete.** The client's `tuist coverage complete` signals that the commit's pipeline finished. A complete commit's per-file figures are then stored as deltas (`Coverage.Deltas`, `coverage_file_deltas`).
5. **Read.** The pages read totals and trends from `coverage_commits`, files and targets from the deltas, and a file's details from the raw `run` rows.

## Figures

A commit's coverage is either exact or explicitly not. `coverage_commits.reported_kind` says which:

| Kind | When | In trends and baselines |
| --- | --- | --- |
| `measured` | The runs listed their candidates (the enumerated tests) and skipped none of them. | Yes |
| `reported` | The runs skipped tests, and every one of them was carried forward exactly, with no file left out. | Yes |
| `observed` | Anything else. The figure is what the runs measured, and `gap_reasons` says why it isn't exact. | No |

A commit is `observed` before anything is carried when:

- **The runs listed no candidates.** What they skipped can't be told, whatever their `partial` flag says. Nothing is inferred from the flag.
- **A scheme's runs reused code they couldn't measure** (`uninstrumented_code`). A binary cache provides prebuilt code without coverage counters, so what the tests executed in it is unknown. That applies to a scheme when one of its runs reused such code and none of its runs executed every test from sources (`Coverage.Instrumentation`). Each build system says which of its runs reused code: Xcode from the targets each run took from the binary cache (`Coverage.Xcode`). Build systems that reuse nothing say none.
- **A target selective testing skipped has tests no run listed** (`no_evidence`). It was pruned from the workspace, and no ancestor run listed its tests, so what it would have covered is unknown.
- **A scheme's coverage only came from CI runs on a dirty checkout** (`dirty_run_excluded`). Those runs measured code that isn't the commit's, and never count.

Rows folded before these rules can still be `partial`. They're read like `observed` (`Coverage.Commits.incomplete?/1`) until they're folded again.

## Carried coverage

A run that skips tests measures less than the commit is covered by. `Tuist.Tests.Coverage.Reported` fills in the tests it skipped with the coverage they had in an earlier run, wherever that coverage provably still applies. Carrying is **all or nothing**: when one skipped test or one file can't be accounted for exactly, nothing is carried and the figure is `observed`, with `gap_reasons` saying why.

The skipped tests are the commit's candidates minus the tests its runs executed. For a scheme selective testing skipped as a whole, or a test target a generated project left out of the workspace, the candidates come from the nearest ancestor run that listed them.

### How it is decided

1. **The commit changes a tracked file.** If the commit's tracked files (`Package.resolved`, `Project.swift`, `*.xcconfig`, … see `Tuist.GitHistory` `tracked_file_globs`) differ from its first parent's, nothing is carried, and no evidence is read: every ancestor's evidence predates the change. When either listing is missing, this step is skipped and step 3 checks each source instead.
2. **Group the skipped tests into units, each with one source run.**
   - A test target selective testing skipped is one unit, carried from its `target` evidence. Only ancestor runs that hashed the target the same way as the commit's run qualify: the same hash means the same inputs, so the same tests over the same code. Among those, the nearest wins.
   - Every other skipped test is a unit of its own, carried from its `test` evidence plus its suite's `suite` evidence, from the nearest ancestor run that holds it. That includes the tests of a skipped target that couldn't be carried whole.
   - The nearest run is fewest commits back, then newest, among the clean-checkout runs on the commit's ancestors within the history window. For tests it's picked in ClickHouse, a chunk of runs at a time, nearest first.
   - A test with no source is a gap, and the reason says why from what the ancestor runs collected: `no_ancestor`, `collection_off`, `evidence_expired`, `not_linked`, `overlapped` or `no_evidence`.
3. **Check that each unit's source still applies.** All of these must hold:
   1. The test passed in the source run, or the target had no failing test there (`test_failed`).
   2. The tracked files are identical at the source commit and at the commit (`tracked_file_changed`, or `listing_missing` when a listing isn't stored).
   3. The evidence holds lines, not only paths, for every file that counts (`evidence_without_lines`).
   4. Every file the unit executed has the same Git blob at the commit as at the source commit (`executed_file_changed`). This applies to whole targets too, which catches an input outside the declared dependency graph. Only files Git tracks count: a submodule's file has no blob to compare.

   These checks read which files each unit's evidence touches and whether it recorded lines, never the lines themselves.
4. **Carry.** Only when every unit passes are the lines read: the units' lines on the files that count are merged per file in ClickHouse, which returns one set of lines per file. A file counts when it's product code, not test code, isn't an excluded path, and the source run reported it.

### What it does to each file

- **A file a run at the commit measured:** a line is covered when the commit's runs covered it or it was carried. Only the file's executable lines at the commit count.
- **A file only the source compiled:** its executable lines come from the source run, and its covered lines are the carried ones.
- **A file no run at the commit compiled** (a selective run builds part of the project): the nearest ancestor that measured the commit's schemes says which files exist. With the same blob, the file keeps that ancestor's executable lines, and its covered lines are the carried ones. If the ancestor covered more than was carried (`unbuilt_file_uncarried`), its blob changed (`unbuilt_file_changed`), or there's no such ancestor or listing (`unbuilt_file_unknown`), the figure is `observed`. A file that's gone from the listing is dropped.

A carried line has no execution count, because no run at the commit executed it.

### Known limits

- The ancestor that says which files a selective run didn't compile comes from `Commits.nearest_measured_ancestor/4`, which can be an `observed` commit. Only the default branch's full runs make reliable ancestors.
- Evidence records what ran, so it can't see compile-time dependencies: a changed macro, a constant folded at compile time, or a type a test uses only when compiling. The blob check doesn't catch a change to such a file unless the unit also executed it.

## Storage

Scopes exist only in the raw per-run rows. Everything kept for longer is derived from them per commit.

| Table | Database | What it holds | Retention |
| --- | --- | --- | --- |
| `coverage_files` | ClickHouse | The raw rows of every scope, one set per run and shard report. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90) |
| `coverage_runs` | ClickHouse | Each run's totals. | `TUIST_COVERAGE_RUN_RETENTION_DAYS` (365) |
| `test_run_enumerated_tests` | ClickHouse | The tests each run could have executed. | Like `coverage_files` |
| `coverage_commits` | PostgreSQL | Each commit's figure and totals: the union of its runs' `run` rows, with carried coverage applied when `reported`. | `TUIST_COVERAGE_COMMIT_RETENTION_DAYS` (1095), or `TUIST_COVERAGE_PULL_REQUEST_COMMIT_RETENTION_DAYS` (90) for a pull request's own commits |
| `coverage_file_deltas` | ClickHouse | A complete commit's per-file `covered_lines` and `executable_lines`, carried coverage applied, stored only where they differ from the previous complete commit on its ref. No lines and no scopes. | `TUIST_COVERAGE_COMMIT_RETENTION_DAYS`, by commit date |
| `coverage_commit_targets` | ClickHouse | A complete commit's targets. | `TUIST_COVERAGE_COMMIT_RETENTION_DAYS`, by commit date |

Which of them the pages read:

- A commit's and a branch's totals and trend come from `coverage_commits`.
- The files table, the targets, the changed files and a file's trend come from the deltas when they are current, and otherwise from the raw rows (`Tuist.Tests.Coverage.Deltas`).
- A file's page at a commit (its figures, functions, per-line counts and carried lines) reads the raw `coverage_files` rows. Once those expire, a file's trend is still there, but its details at older commits are not.

## Xcode

Xcode measures only the `run` scope itself. The other three come from [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution), a package linked into the test targets that attributes Xcode's coverage counters to the code each test process and each test executed.

| Scope | Source | Requirements |
| --- | --- | --- |
| `run` | Xcode's coverage, read with `xccov` (`view --report` for targets and functions, `view --archive` for per-line execution counts), on the macOS xcresult processor for uploaded result bundles or on the client in local mode. | `-enableCodeCoverage YES`. Files compiled only into `.xctest` bundles are flagged as test code and left out of every figure. |
| `target` | TestCoverageAttribution: everything the target's test process executed. | The package linked into the test target, and evidence collection on (`TUIST_COVERAGE_EVIDENCE=1`, which makes Tuist set `TEST_COVERAGE_ATTRIBUTION_DIR` for the test process). Works with parallel testing and with Swift Testing suites that lack the trait. |
| `test` | TestCoverageAttribution: one record per test. | Same as `target`. XCTest needs nothing more. Swift Testing needs the `.coverageAttribution` trait on its suites. Tests must run one at a time (`-parallel-testing-enabled NO`): a test that overlaps another is flagged as overlapped and gets no evidence of its own (`test_case_runs.coverage_evidence` = `overlapped`). |
| `suite` | TestCoverageAttribution: the records of what ran between tests. | Same as `test`. |

**Enumerated tests.** Tuist lists every test the run could execute with `xcodebuild -enumerate-tests`, over the built products and with the run's filters removed, so `-only-testing` doesn't narrow it. The list goes into the result bundle as `tuist_test_enumeration.json`.

**What makes a run partial.** The CLI marks a run's coverage partial when it left tests out: `-only-testing`, `-skip-testing` (quarantined tests aside), Tuist's `--test-targets` and `--skip-test-targets`, or a selective-testing hit.

**The binary cache.** A target taken from the binary cache is a prebuilt binary without coverage counters. The run still reports coverage, but not for that target's code, and the CLI doesn't mark it partial for it. The server reads it from the run's targets (`xcode_targets.binary_cache_hit`) instead. A scheme is `observed` when one of its runs took a target from the cache and none of its runs ran every test without it. The Tuist project's own coverage pipeline (`.github/workflows/coverage.yml`) disables the cache (`--no-binary-cache`) and selective testing for that reason.

Limitations that apply to all the attributed scopes:

- UI tests record nothing about the app, because the app's code runs in a process that doesn't link the package.
- Images loaded after the first test starts, such as a framework the tests `dlopen`, are missing from the records.
- Recording works on macOS and the iOS simulator only, not on devices.
- When tests run in parallel inside one process, coverage counters must be bumped atomically (`OTHER_SWIFT_FLAGS=$(inherited) -Xllvm -instrprof-atomic-counter-update-all`). Plain increments lose counts, which `xccov` reports as negative counts and as lines covered that never ran.

## Mix

`mix tuist.test --cover` (the `tuist_ex` package) measures only the `run` scope, read from Erlang's `cover` once the suite finishes, and sends it as the `coverage` block (`tool` `cover`). An OTP application is a target, and the files under the project's test paths are test code. Mix collects no `target`, `suite` or `test` evidence.

| Scope | Source | Requirements |
| --- | --- | --- |
| `run` | Erlang's `cover`. | `--cover`. |
| `target`, `suite`, `test` | Not collected. | |

A run is marked partial when its arguments leave tests out: `--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures`, or explicit test files or lines (`TuistEx.Analytics.Coverage.partial?/1`).

Mix runs don't list their candidates yet (tuist/tuist#13997 adds it), so every Mix commit is `observed` for now. Once they do, a commit whose runs skipped nothing is `measured`. A partial run still has no evidence to carry from, so its commit stays `observed`.
