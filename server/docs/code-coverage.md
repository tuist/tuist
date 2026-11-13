# Code coverage

How Tuist collects, stores and shows code coverage today. Mix and Cargo projects have it in every account; every other build system is in early access behind `Tuist.FeatureFlags.xcode_coverage_enabled?/2`. `Tuist.FeatureFlags.coverage_enabled?/3` decides per project.

## Immutable shard plans

Immutable (version-1) shard plans are disabled in code for every account (`Tuist.FeatureFlags.immutable_shard_reports_enabled?/2`), so every new plan is a legacy one. Coverage's receipt-ordered files, evidence and mutable totals cannot safely describe producer-ordered attempts on a version-1 plan yet, and test selection reads that coverage. They come back once coverage reads version-1 reports.

If coverage is enabled after such a plan exists, the persisted reporting contract still wins. Version-1 reports keep their test results but do not ingest coverage or evidence; they record `coverage_enabled = false` and an empty `coverage_evidence_status`. Direct publication/evidence calls skip these runs, and queued uploaded-coverage jobs cancel before downloading. They neither become coverage sources nor introduce gaps into a commit's figure. Unsharded runs and legacy plans retain the model below. See [immutable shard reporting](shard-workflow-consistency.md) for enrollment and compatibility requirements.

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
| `target`, `suite`, `test` | Never shown on their own. They show up only through carried coverage: the commit's and each file's figures include the lines carried from skipped tests, without saying which ones. Why a figure is `partial` (`coverage_commits.gap_reasons`) is stored but not displayed yet. |

## How the data flows

1. **Measure.** The client runs the tests with coverage on and reports the `run` scope, and what Tuist skipped: the selective-testing hit and hash of each target (on the run's command event, `xcode_targets`) and the run's `skip_test_identifiers` and `only_test_identifiers`. It also reports whether the run was set up to collect coverage (`coverage_enabled`), even when selective testing skipped every test. On Xcode, test targets that link TestCoverageAttribution also record the `target`, `suite` and `test` evidence when evidence collection is on. On Cargo, `tuist cargo` records `target` evidence, and under nextest `test` evidence too (see [Cargo](#cargo)).
2. **Ingest.** An Xcode result bundle is parsed either by the macOS xcresult processor (remote processing) or by the CLI itself (local mode, which uploads the coverage, handed to `Tests.Workers.PublishCoverageWorker`, and sends the evidence with the run). `Tests.create_test/1` stores them: `Coverage.publish/4` the `run` rows and the run's totals in `coverage_runs`, and `Coverage.Evidence.record/4` the evidence rows.
3. **Fold.** A few seconds after each report, `Coverage.Workers.CommitWorker` recomputes the commit (`Coverage.Commits.recompute/3`). It merges the `run` rows of the commit's clean runs and asks `Coverage.Reported.compute/3` for the commit's figure: `measured`, `reported` or `partial` (see [Figures](#figures)). The result is written to `coverage_commits`.
4. **Complete.** The client's `tuist coverage complete` signals that the commit's pipeline finished. A complete commit's per-file figures are then stored as deltas (`Coverage.Deltas`, `coverage_file_deltas`).
5. **Read.** The pages read totals and trends from `coverage_commits`, files and targets from the deltas, and a file's details from the raw `run` rows.

## Figures

`coverage_commits.reported_kind` says how exact a commit's figure is:

| Kind | When | In trends and baselines |
| --- | --- | --- |
| `measured` | Tuist skipped nothing, quarantined tests aside, and no scheme was left partial for a reason nothing explains. | Yes |
| `reported` | Tuist skipped tests, and every one of them was carried forward, with no file left out. | Yes |
| `partial` | Some coverage couldn't be determined; the figure is a lower bound and `gap_reasons` says why. | No |

Besides the skipped tests that couldn't be carried (see [Carried coverage](#carried-coverage)), a commit is `partial` when:

- **Every run of a scheme was narrowed by its caller** (`caller_selected_tests`, `-only-testing`). Tuist didn't skip the rest, so there's nothing to carry it from.
- **Selective testing skipped a target no ancestor run executed** (`target_without_history`), so which tests it holds is unknown.
- **A scheme's runs reused code they couldn't measure** (`uninstrumented_code`). A binary cache provides prebuilt code, and a prebuilt binary carries coverage counters only when it was built with coverage, so what the tests executed in a plain one is unknown. That applies to a target when one of its scheme's runs took it from the cache without counters and no run of the scheme that executed every test built it from source or took an instrumented binary (`Coverage.Instrumentation.incomplete_targets/2`). Each build system says which targets each of its runs took that way: Xcode from the runs' targets, their hit and whether the client found counters in the binary (`Coverage.Xcode`, `xcode_targets.binary_cache_instrumented`). Build systems that reuse nothing say none. A run that took any repository target from the cache without counters is no source of carried coverage at all: its tests executed code that went uncounted, and which test targets linked it is not worth a dependency walk per fold, since a coverage run's hits are all instrumented or all plain once the cache key tells them apart.
- **Every run of a scheme was partial and nothing names what was left out**, for example when no command event reached the server.
- **A scheme's coverage only came from CI runs on a dirty checkout** (`dirty_run_excluded`). Those runs measured code that isn't the commit's, and never count. A clean run of the scheme with coverage off (`coverage_enabled` `false`) doesn't make up for them.

## Carried coverage

A run that skips tests measures less than the commit is covered by. `Tuist.Tests.Coverage.Reported` fills in the tests Tuist skipped with the coverage they had in an earlier run, wherever that coverage provably still applies. Whatever can't be carried is a **gap**: the rest is still carried, and the figure is `partial`.

### What was skipped

What was skipped comes from what Tuist itself skipped, not from a list of the tests a run could have executed:

| Skipped by | What the server has | What it carries |
| --- | --- | --- |
| Selective testing (a target pruned, or a scheme skipped whole) | the hit and hash per target on the run's command event | the target's tests, taken from the run recorded under its hash, or else from the commit's baseline while the target's test files are unchanged |
| `--skip-test-targets`, `-skip-testing` | `test_runs.skip_test_identifiers` | the tests each identifier names (`Module`, `Module/Suite`, `Module/Suite/test`, with or without `()`): a named test directly, a target or suite against the target's tests as above |
| The caller's `-only-testing` | `test_runs.only_test_identifiers` | nothing; a scheme whose every run was narrowed is a gap |
| Quarantine "skip" | nothing | nothing, and it's no gap: a quarantined test is outside the suite |

A quarantined test isn't part of the figure. The client leaves the tests quarantine skipped out of `skip_test_identifiers`, as it does when it decides whether a run's coverage is partial, so a run that skipped only them is a full run: its commit can be `measured` and serve as a baseline. Quarantine names single tests, so it never skips a whole target or suite. A `--skip-test-targets` entry identical to a quarantine skip is left out with it; a `-skip-testing` the caller passed to xcodebuild is always reported. Clients older than this change still report the tests `tuist test` skipped for quarantine as skipped, and the server can't tell them apart from the caller's, so those runs keep their commits `partial` until the client is updated. `tuist xcodebuild test` never reported them.

What another run at the commit executed isn't skipped, whichever run skipped it. A test counts as executed when any run that measured the commit ran it. A whole target counts only for a run of the same scheme, since another scheme's test plan can run other tests of the same target. A run that measured the commit executed a target whole when its `test_module_runs` row for the target holds tests and its `-only-testing` doesn't name it (read by run, so it costs the runs' own rows, not the project's test history): a full run beside a selective one, as when one pipeline tests selectively and another runs every test, measures what the selective one skipped. Only the tests that run's own skip identifiers name stay skipped. A run whose caller narrowed a target executed only the tests it has runs for, so the rest of the target stays skipped.

Only runs set up to collect coverage say what was skipped. A run that skipped everything measured nothing either way, so the client reports `test_runs.coverage_enabled`: another pipeline's test job on the same commit, which runs without coverage, has it `false` and its hits and skips are left out. Runs from clients that don't report it (`NULL`) still count.

No ancestor runs are walked: see [Search bounds](#search-bounds).

### The pipeline

A commit's figure is folded again whenever more of its data lands: another run, shard or scheme, a run's command event, or the completion signal (`Coverage.Workers.CommitWorker`). Every step is safe to repeat, and the last fold wins.

1. **Store and merge.** Each report is stored per run and shard (`coverage_files`, `coverage_runs`). The fold merges every clean run of the commit: a line is covered when any run covered it, and a file counts once however many schemes compiled it.
2. **Find what was skipped.** Only runs set up to collect coverage are read (`coverage_enabled` isn't `false`). What they skipped is the targets selective testing hit, with their hashes; the tests the runs' skip identifiers name (`--skip-test-targets`, `-skip-testing`, but not quarantine: see [What was skipped](#what-was-skipped)); and whether the caller narrowed a scheme's runs (`only_test_identifiers`). A target a run of the same scheme executed, or a named test any run executed, among the runs that measured the commit, is dropped first, before anything below is decided, so it is never carried nor a gap (`tracked_file_changed`, `test_list_changed`, `target_without_history`); a target counts only when that run's `-only-testing` doesn't name it, and a `Module` or `Module/Suite` identifier only when none of that run's identifiers name the target. A skipped target's tests come from the run recorded under its hash (`coverage_target_sources`), whatever branch it ran on, since the same hash means the same tests. Otherwise they come from the commit's **baseline**: a baseline run of the scheme that skipped the target, or, when none of those ran it, another scheme's baseline run that did, as long as none of the target's test files changed since the baseline and none was added beside them. If one did, the target is a gap (`test_list_changed`). Without both commits' listings, the baseline's tests are taken as they were. If the baseline didn't run the target, it's `target_without_history`. An identifier naming a test (`Module/Suite/test`) resolves to that test directly. Tests that ran at the commit anyway aren't skipped. See [What was skipped](#what-was-skipped).
3. **Measured?** If nothing was skipped, no scheme was narrowed, and no run reused uninstrumented code (`uninstrumented_code`), the figure is `measured` and the fold stops here. `Commits` then makes a `measured` figure `partial` when every run of one of its schemes is partial, for example a run still missing a shard with no complete run of the scheme beside it.
4. **Tracked files changed?** If the commit's tracked files differ from every parent's, nothing is carried. They're the project's build system's build inputs (`Tuist.GitHistory` `tracked_file_globs`): Xcode's are `Package.resolved`, `Project.swift`, `*.xcconfig` and the like, Mix's are `mix.exs`, `mix.lock` and `config/**` (see [Mix](#mix)), Cargo's are `Cargo.toml`, `Cargo.lock` and `build.rs` (see [Cargo](#cargo)), and a build system without its own list uses Xcode's. Another toolchain's build files in the same repository aren't tracked. Every earlier run's evidence predates the change, so the figure is `partial` (`tracked_file_changed`) and no evidence is read. In the code this check runs right after step 2 drops what another run executed, before any skipped target's tests are looked up: when anything is left, none of it is resolved, so such a commit reports no skipped tests (`skipped_tests_count` 0). A merge whose tracked files match one parent's still carries from that side. A commit with no repository or no ancestor carries nothing either (`no_ancestor`).
5. **Carry whole targets.** This step runs only for a skipped target that has a selective-testing hash and whose earlier runs recorded `target` evidence for it. Its source is the latest clean run, on any branch, that executed it whole with that hash, passed it and recorded its evidence (`Coverage.TargetSources`).
   - **We trust the hash.** It covers the target's sources, its tests and every dependency, the test host included. So the same hash means the same tests over the same code, and the source's files aren't compared blob by blob.
   - What's still checked: the target passed there (the index records only passing runs), the source's evidence holds lines for the files that count, and the tracked files are the same at the source's commit.
   - A target with a hash but no recorded run carries from the baseline, if a baseline run holds its evidence and hashed it the same way. That happens when a run's hashes landed after its fold, in local inspect mode.
6. **Carry tests one by one.** This step runs only for skipped tests whose earlier runs recorded `test` evidence (and their suite's `suite` evidence): the tests of a target that couldn't be carried whole, and the tests skipped by identifier.
   - The source is the latest run, on any branch, whose **version** of the test the commit reproduces (`Coverage.TestEvidence`, the lookup test selection shares; versions are stored by `Coverage.TestSources`). A version is the test's `test_case_id` and a fingerprint of the repository files the test and its suite executed, with their blobs. The commit recomputes it over the same files with its own blobs. A match means that run executed exactly these files, so here the blobs are compared, through the fingerprint.
   - Versions exist but none matches: `executed_file_changed`. The matching version's test failed: `test_failed`. It has files without lines that count: `evidence_without_lines`. The source commit's tracked files differ: `tracked_file_changed`.
   - A test with no versions is explained by what the baseline collected: `no_ancestor` (no baseline), `collection_off`, `evidence_expired`, `not_linked`, `overlapped` or `no_evidence`.
7. **Complete the file set.** A selective run builds only part of the project. A file no run at the commit compiled takes its executable lines from the nearest ancestor that measured the commit's schemes, and its covered lines are the carried ones. It's a gap if that ancestor covered more than was carried (`unbuilt_file_uncarried`), if its blob changed (`unbuilt_file_changed`), or if there's no such ancestor or listing (`unbuilt_file_unknown`). See [What it does to each file](#what-it-does-to-each-file).
8. **Result.**
   - `reported`: every skipped test was carried and no file is a gap.
   - `partial`: anything is left over. That includes a gap from steps 2–7, a scheme only dirty runs measured (`dirty_run_excluded`), a narrowed scheme (`caller_selected_tests`), a scheme every run of which is partial (a missing shard, with no complete run beside it), or uninstrumented code.
   - The reasons are stored with the figure (`coverage_commits.gap_reasons`).

The carried lines are read last, for the sources that passed, merged per file in ClickHouse, so a fold receives one set of lines per file however many tests and runs it carries. A file counts when it's product code, not test code, isn't an excluded path, and the source run reported it.

**What the coverage holds decides which carry steps can run.** A run that reported only `run` coverage gives nothing to carry: its commits can be `measured`, or `partial` when tests were skipped. `target` evidence enables step 5, and `test` and `suite` evidence enable step 6. A test target that doesn't link TestCoverageAttribution, and every Swift Testing test (`test` and `suite` evidence is recorded for XCTest and XCUITest only), records only `target` evidence, so its skipped tests are carried only with their whole target. Mix records only `run` coverage today, so a Mix commit that skipped tests is `partial`.

### Search bounds

Steps 5 and 6 don't search history: both read an index keyed by what makes a source valid (a target's hash, a test's version). The only history a fold reads is the commit's **baseline**: for each of its schemes, the runs of the nearest ancestor whose figure was `measured`, so every test of the scheme ran (`Commits.nearest_measured_ancestor/5` with `kind: "measured"`). It's found once per fold, with a first-parent probe over `coverage_commits` in PostgreSQL, and reused for:

| Need | From the baseline |
| --- | --- |
| Step 2, a skipped target's tests when no run is recorded under its hash, or for `Module` and `Module/Suite` identifiers | the tests the baseline ran in that target, while its test files are unchanged |
| Step 5, a target with no recorded run | the baseline run, if it holds the target's evidence and hashed it the same way |
| Step 6, explaining a test with no versions | what the baseline collected |

Step 7 reads the same kind of ancestor through `Commits.nearest_measured_ancestor/4`, which also accepts a `partial` one. No run walk is left: the search is bounded by the history window (5,000 commits, `GitHistory.settings/1`), which is also how far the commit graph is kept. Evidence expires after 90 days (`TUIST_COVERAGE_FILE_RETENTION_DAYS`), and that retention is the real limit on how old a source can be.

### Baseline runs

A full run of each scheme on the default branch is what the pipeline leans on:
- **It refreshes evidence** before it expires, so a target that stays skippable for months still has something to carry from.
- **It's the measured ancestor** step 7 reads, so files the commit didn't compile are compared against a recent state.
- **It's the baseline** a fold reads when an index has no answer: a skipped target's tests, the fallback source for a target, and the explanation of a test with nothing to carry.

A full run on every merge into the default branch is ideal. Daily or weekly can be enough: what matters is how much changes between baselines.
- The more files change after a baseline, the more of them a selective run neither compiles nor finds unchanged (`unbuilt_file_changed`).
- A changed target's test files more often differ from the baseline's, which makes it a gap (`test_list_changed`).

A repository that changes a few files a week does well with a weekly baseline; one with many merges a day needs one per merge or per day. Either way it has to run more often than the 90-day evidence retention, and without the binary cache, or it counts as uninstrumented (`uninstrumented_code`).

### What it does to each file

- **A file a run at the commit measured:** a line is covered when the commit's runs covered it or it was carried. Only the file's executable lines at the commit count.
- **A file only the source compiled:** its executable lines come from the source run, and its covered lines are the carried ones.
- **A file no run at the commit compiled** (a selective run builds part of the project): the nearest ancestor that measured the commit's schemes says which files exist. With the same blob, the file keeps that ancestor's executable lines, and its covered lines are the carried ones. If the ancestor covered more than was carried (`unbuilt_file_uncarried`), its blob changed (`unbuilt_file_changed`), or there's no such ancestor or listing (`unbuilt_file_unknown`), the file is a gap and the figure is `partial`. A file that's gone from the listing is dropped.

A carried line has no execution count, because no run at the commit executed it.

### Known limits

- The ancestor that says which files a selective run didn't compile comes from `Commits.nearest_measured_ancestor/4`, which can be a `partial` commit. Only the default branch's full runs make reliable ancestors.
- Which tests a skipped target holds comes from the ancestor run that executed it: a test added since then isn't carried, nor counted as a gap.
- Evidence records what ran, so it can't see compile-time dependencies: a changed macro, a constant folded at compile time, or a type a test uses only when compiling. A test's version doesn't change for such a file unless the test also executed it. A target's hash does, when the file is in the target or one of its dependencies.
- Trusting the target hash means an input outside the project graph (a file read at runtime, generated code outside the graph) doesn't block carrying a target whose hash didn't change. Selective testing makes the same trust when it skips the target.

## Storage

Scopes exist only in the raw per-run rows. Everything kept for longer is derived from them per commit.

| Table | Database | What it holds | Retention |
| --- | --- | --- | --- |
| `coverage_files` | ClickHouse | The raw rows of every scope, one set per run and shard report. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90) |
| `coverage_runs` | ClickHouse | Each run's totals. | `TUIST_COVERAGE_RUN_RETENTION_DAYS` (365) |
| `coverage_commits` | PostgreSQL | Each commit's figure and totals: the union of its runs' `run` rows, with carried coverage applied. | `TUIST_COVERAGE_COMMIT_RETENTION_DAYS` (1095), or `TUIST_COVERAGE_PULL_REQUEST_COMMIT_RETENTION_DAYS` (90) for a pull request's own commits |
| `coverage_file_deltas` | ClickHouse | A complete commit's per-file `covered_lines` and `executable_lines`, carried coverage applied, stored only where they differ from the previous complete commit on its ref. No lines and no scopes. | `TUIST_COVERAGE_COMMIT_RETENTION_DAYS`, by commit date |
| `coverage_commit_targets` | ClickHouse | A complete commit's targets. | `TUIST_COVERAGE_COMMIT_RETENTION_DAYS`, by commit date |
| `git_commit_files` | ClickHouse | A commit's file listing (`git ls-tree -r`: path, blob and mode per file), uploaded once per commit by a clean checkout and keyed by repository and commit (`Tuist.GitHistory.CommitFile`). It's what coverage is measured against (files no run measured), where the tracked files come from (step 4), what the diff rule compares against the baseline (step 2), where a file's blob comes from when a run reported none (test fingerprints), and what tells whether an unbuilt file is unchanged since the commit it takes its lines from (step 7). | `TUIST_COVERAGE_FILE_RETENTION_DAYS`, by insertion |
| `git_file_changes` | ClickHouse | The paths a listed commit changed against the nearest listed commit below it on the first-parent tree, written from its listing (or, for a clean checkout's coverage-based selection, from the diff against a baseline whose file changes are written: `FileChanges.write_from_diff/5`, with a listing row whose files were never uploaded, `staged` false, which counts as missing once the changes aren't current) and keyed by the commit's place (`Tuist.GitHistory.FileChanges`, `Tuist.GitHistory.FileChange`): a commit's files are each path's newest row along its ref and the refs it forks from. Written for every whole listing once a ref owns the commit; a commit no branch or pull request owns (a pull request's superseded merge commit, a commit a force-push dropped) is given a detached ref of its own for it (`GitHistory.detach/3`), forking where its first parents reach a commit a ref owns, which only the file changes read: commit coverage and the history walks still see the commit as owned by no ref. A ref advanced through the commit takes it over, and the detached ref is dropped then, when the place it forks at is released, on a rebuild of the refs, and once its rows expired. A write that finds the listing's files not all on its replica yet is tried again, up to once an hour, until they are or the listing expires, and a write whose job was lost is queued again once a day. Listings arrive in any order: a commit written below others first gives the written commits right above it a row of their own for each path involved, so their files stay what their listings said. A commit that moves (a fast-forward, a rebuild of the refs) is written again at its new place, from its listing or, once that expired, from the rows it left at the old one; rows that would move up their own ref are retired instead, and that commit's files are unknown until it is listed again. Once written it is what every read of the commit's files uses (`GitHistory.commit_files/3`, `files_in/3`, `blobs_at/3`, `tracked_files/3`, and `changed_files/4` for what differs between two commits, which reads only the paths with a row on one commit's chain and not the other's); until then, and for a commit whose first parents reach no commit a ref owns, the same functions read the listing in `git_commit_files`. | Kept on a ref that forks from none; on any other, `TUIST_COVERAGE_FILE_RETENTION_DAYS` after the ref's rows were last renewed (a write that finds less than half of it left renews them) |
| `coverage_target_sources` | ClickHouse | One row per target and selective-testing hash: the passing run that recorded `target` evidence under it. Written when a commit is folded; carries skipped targets (pipeline step 5). | `TUIST_COVERAGE_FILE_RETENTION_DAYS`, by insertion |
| `coverage_test_sources` | ClickHouse | One row per test case and fingerprint (the files the test and its suite ran, with their blobs): the run that recorded that version, its paths and whether it passed. Written when a commit is folded; carries skipped tests (pipeline step 6). | `TUIST_COVERAGE_FILE_RETENTION_DAYS`, by insertion |

Which of them the pages read:

- A commit's and a branch's totals and trend come from `coverage_commits`.
- The files table, the targets, the changed files and a file's trend come from the deltas when they are current, and otherwise from the raw rows (`Tuist.Tests.Coverage.Deltas`).
- A file's page at a commit (its figures, functions and per-line counts) reads the raw `coverage_files` rows. Once those expire, a file's trend is still there, but its details at older commits are not.

## Xcode

Xcode measures only the `run` scope itself. The CLI reads `target` from the raw profiles Xcode writes per test process. `test` and `suite` come from [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution), a package linked into the test targets that attributes Xcode's coverage counters to the code each test executed.

| Scope | Source | Requirements |
| --- | --- | --- |
| `run` | Xcode's coverage, read with `xccov` (`view --report` for targets and functions, `view --archive` for per-line execution counts), on the macOS xcresult processor for uploaded result bundles or on the client in local mode. | `-enableCodeCoverage YES`. Files compiled only into `.xctest` bundles are flagged as test code and left out of every figure. |
| `target` | Xcode's raw profiles: everything the target's test processes executed, the host app's launch included. Xcode writes one `<uuid>-<pid>.profraw` per process next to `Coverage.profdata`. The CLI matches each to the test bundle whose own functions ran in it, merges each target's profiles, and reports them with `llvm-cov`. When none can be read, the union of TestCoverageAttribution's records stands in. A UI test target also gets what the app it launched executed, as in the `test` row. | A run that uploads coverage, on macOS or a simulator. Nothing to link. Works with parallel testing, XCTest and Swift Testing, so Swift Testing tests still get per-target coverage. A UI-tested app's own process needs the package linked into the UI test target. |
| `test` | TestCoverageAttribution: one record per XCTest or XCUITest test. For a UI test, also what the app it launched executed: the package records the pid of each `XCUIApplication` launch with the running test (`launches.tsv`), and the CLI reports the app's own `<uuid>-<pid>.profraw` with `llvm-cov` over the app's images. A launch outside a test, such as in a class `setUp`, goes to the `suite`. | The package linked into the test target, and a run that uploads coverage (Tuist then sets `TEST_COVERAGE_ATTRIBUTION_DIR` for the test process). XCTest and XCUITest need nothing more. Swift Testing isn't supported: its tests get no `test` or `suite` evidence, only the `target` evidence of their module (see below). Each test process must run one test at a time, but the run needn't be serial: Xcode's parallel testing runs XCTest and XCUITest tests in separate clone processes that each run one test at a time, so their evidence matches a serial run. A test that overlaps another in the same process, as with Swift Testing's parallel default, is flagged as overlapped and gets no evidence of its own (`test_case_runs.coverage_evidence` = `overlapped`). The app side of a UI test is per process too. A retried UI test gets the union of its attempts' launches. |
| `suite` | TestCoverageAttribution: the records of what ran between tests. | Same as `test`. |

**What makes a run partial.** The CLI marks a run's coverage partial when it left tests out: `-only-testing`, `-skip-testing` (quarantined tests aside), Tuist's `--test-targets` and `--skip-test-targets`, or a selective-testing hit.

**Keeping each run's coverage.** `tuist test --coverage-output-path <directory>` (or `TUIST_TEST_COVERAGE_OUTPUT_PATH`) also writes the coverage the CLI sends for a run to `<directory>/<result bundle name>.lcov`, for teams that merge a sharded run's coverage into their own reports (`lcov -a`, Istanbul). Each product file is an LCOV section with its path relative to the repository, its functions with their execution counts, and its executable lines with theirs; test files are left out. It is the report measured with `llvm-cov`, binary-cached targets included when the cache holds their instrumented variant, or `xccov`'s when the client could not export one. A remotely processed run without a client export writes nothing, since the server reads that run's coverage. Writing the file never fails the run.

**The binary cache.** A target taken from the binary cache is a prebuilt binary without coverage counters. The run still reports coverage, but not for that target's code, and the CLI doesn't mark it partial for it. The server reads it from the run's targets (`xcode_targets.binary_cache_hit`) instead, leaving out remote packages (a non-empty `external_hash`): their code is outside the repository, so no coverage is kept for it anyway, and the default cache profile caches them. A local package's targets count. The client also reports, per hit, whether the cached binary carries coverage counters (`binary_cache_instrumented`, read off the binary's `__llvm_covmap`): an instrumented hit counts as measured. A hit counts only when its binary replaced the target: the client fetches a binary for every hit but replaces a target only when its direct dependencies were all replaced, so a hit above a miss is built from source, or not built at all, and its binary goes unused. The server applies the same rule to the run's targets and their `dependencies` (`xcode_targets.dependencies`). A scheme is `partial` (`uninstrumented_code`) when one of its runs took a target from the cache without counters and none of its full runs built that target from source or took it instrumented. A run whose every product target came that way measures no product line, and still counts as a run of the commit because its reports listed files (`coverage_runs.files`); only a run that reported no file at all gathered no coverage. The commit's Targets tab lists the targets taken that way as not measured, by the names the run reported, beside the measured products (`Commits.unmeasured_targets/2`), and the Incomplete status says the code came from the cache without counters. The Tuist project's own coverage pipeline (`.github/workflows/tuist-project-tests.yml`) runs its full runs on main without selective testing against the binary cache's coverage variant, which it warms first, so its cached targets count as measured.

**Swift Testing.** Test-scoped evidence (`test` and `suite`) works for XCTest and XCUITest only. TestCoverageAttribution's `.coverageAttribution` trait isn't a supported setup: it only works with serial runs, and Swift Testing can't skip a test from a trait yet, so a test with evidence couldn't be left out of a run anyway. Swift Testing tests still count in the `run` and `target` scopes, so their code shows in the commit's coverage and a skipped Swift Testing test carries with its whole target, just never on its own. A target that mixes XCTest and Swift Testing gets per-test evidence for its XCTest tests and per-target evidence for the rest.

Limitations that apply to all the attributed scopes:

- A UI test's app evidence relies on Xcode details that aren't a public contract: one `<uuid>-<pid>.profraw` per launch in continuous mode, kept next to `Coverage.profdata` until the next coverage run, and `XCUIApplication`'s private `processID`. Processes the app starts itself, such as extensions, aren't attributed.
- Images loaded after the first test starts, such as a framework the tests `dlopen`, are missing from the records.
- Recording works on macOS and the iOS simulator only, not on devices.
- When tests run in parallel inside one process, coverage counters must be bumped atomically (`OTHER_SWIFT_FLAGS=$(inherited) -Xllvm -instrprof-atomic-counter-update-all`). Plain increments lose counts, which `xccov` reports as negative counts and as lines covered that never ran.

## Mix

`mix tuist.test --cover` (the `tuist_ex` package) measures only the `run` scope, read from Erlang's `cover` once the suite finishes, and sends it as the `coverage` block (`tool` `cover`). An OTP application is a target, and the files under the project's test paths are test code. Mix collects no `target`, `suite` or `test` evidence.

Each executable line belongs to the function whose clause head starts closest above it. Functions the compiler or a macro generates under a `__` name (`__info__/1`, `__schema__/1` and the like, on the line `defmodule`, `schema` or `use` sits on), and `module_info`, aren't listed, but their lines still count for the file, so a file can cover lines no listed function accounts for; its page's Covered lines tooltip says how many. Tuist's figures differ from `mix test --cover`'s own report in two ways: they leave test code out, and they count a line once per file rather than once per module.

| Scope | Source | Requirements |
| --- | --- | --- |
| `run` | The runtime's native line counters, or Erlang's `cover`. | `--cover`. |
| `target`, `suite`, `test` | Not collected. | |

A Mix project's tracked files (step 4 of [the pipeline](#the-pipeline)) are `mix.exs`, `mix.lock`, everything under a `config/` directory, and the toolchain pins `.tool-versions`, `mise.toml` and `.mise.toml`, at any depth, so a Mix project in a subdirectory of a monorepo is covered. A shared `mise.toml` also pins other toolchains, so changing any of them counts as a change.

Erlang's `cover` compiles every module again at the start of each run, so runs count natively instead: the project's modules are instrumented with the runtime's line counters (only those a compile wrote since the last run, and once for every shard when `mix tuist.test.build --cover` built them), and the run switches the runtime to those counters and counts with them, compiling only the modules Mimic copies for `cover` and swapping them for Mimic's copies before any test runs (Mimic keeps a `cover` compiled module's counts across its swaps; a reload resets native counters). Mix's summary and threshold are kept: `mix tuist.test` prints Mix's per-module table from the counts read when the suite finishes and fails the run below `test_coverage: [summary: [threshold: N]]`, except on a shard; it writes no HTML report. A runtime without the JIT, an umbrella's root, or a project that sets its own `test_coverage` tool uses `cover` through Mix's coverage tool. The figures are the same either way, except that native counting also sees code that runs while the application starts, before `cover` would have compiled it, and leaves out lines the compiler proves can never run, which `cover` reports as never covered.

A run is marked partial when it leaves tests out: its own arguments (`--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures`, or explicit test files or lines, `TuistEx.Analytics.Coverage.partial?/1`), or a test excluded because it shares a quarantined test's name. Tests the test helper's own configuration excludes (`ExUnit.start(exclude: ...)`) aren't part of the suite, as tests a test plan disables aren't for Xcode, so they don't make the run partial. It says what it left out the way the Xcode CLI does. A run its arguments limited to the tests they select (`--only`, `--failed`, `--stale`, `--name-pattern`, files or lines, `Coverage.narrowed?/1`) reports the tests it ran in `only_test_identifiers`, so its scheme is `caller_selected_tests` when every run of it was limited. Any other run reports the tests its own `--exclude` options left out, and those that share a quarantined test's name, in `skip_test_identifiers` (`Coverage.excluded_tags/1`, matched against ExUnit's exclusion reason). Their parts are percent-encoded, since describe names such as `create_order/2` hold a `/`. Mix records no per-test evidence, so nothing is carried: those tests are gaps (`collection_off`), unless another run at the commit executed them. A test that was never reported by any run isn't known to the server and is left out silently, as for Xcode. Tests quarantined as skipped are the exception: `mix tuist.test` excludes them, but they don't make the run partial and aren't reported, because a quarantined test is left out on purpose, as if it were removed. The lines only it covered count as uncovered. Tests skipped in code (`@tag :skip`) run as ExUnit skips, not exclusions, and don't make the run partial either, like Xcode's disabled tests.

## Cargo

`tuist cargo test` and `tuist cargo nextest run` measure coverage when the project's `tuist.toml` sets `upload = true` under `[test_insights.coverage]`. `TUIST_COVERAGE_UPLOAD` overrides it for one run (`1` or `0`). The client (`cli/Sources/TuistCargoCommand/CargoCoverage.swift`):

- builds the repository's crates with `-C instrument-coverage`, and its dependencies as a plain build does;
- starts every test process through a target runner that records the process's arguments and gives it a profile of its own;
- reads the profiles with `llvm-profdata` and `llvm-cov`, from the toolchain's `llvm-tools` component, which it installs on a rustup toolchain that lacks it;
- sends the `coverage` block (`tool` `llvm-cov`, the target triple as `platform`) inline, or uploaded first above the server's threshold, together with `coverage_evidence`.

A Cargo package is a target. Its integration tests, benchmarks and examples are test code: the files under `tests/`, `benches/` and `examples/`, and a target of one of those kinds. Each executable line belongs to the function that starts closest above it. A generic function's instantiations, and a function compiled into several test binaries, count once, under the function's demangled path without its generic arguments.

| Scope | Source | Requirements |
| --- | --- | --- |
| `run` | `llvm-cov export` of the run's profiles over the test binaries it executed. | Coverage on, and the toolchain's `llvm-tools` (installed for rustup toolchains). |
| `target` | A test binary's processes. The module is the one the run reports the binary's tests under: `<package>`, `<package>::<target>` or `<package>::bin/<target>`, nextest's binary IDs. | The recording runner. A Cargo configuration file that sets `target.<triple>.runner` replaces it, so such a project gets only the `run` scope. A runner set in the environment is chained. |
| `test` | Nextest only: the process that ran the test alone (`<binary> --exact <name>`). A retried test gets the union of its attempts. | `cargo nextest run`. Plain `cargo test` runs a binary's tests in one process, so its tests are reported as overlapped (`overlapped_tests`) and get no evidence of their own. |
| `suite` | Not collected. Libtest has no setup that runs around a suite's tests. | |

Doctests aren't instrumented (rustdoc builds them without Cargo's flags), so they add nothing to any scope and are never reported as overlapped.

A Cargo project's tracked files (step 4 of [the pipeline](#the-pipeline)) are `Cargo.toml`, `Cargo.lock`, build scripts (`build.rs`, which run at build time and so never show in the tests' coverage), Cargo's configuration (`.cargo/config` and `.cargo/config.toml`), nextest's (`.config/nextest.toml`), and the toolchain pins `rust-toolchain`, `rust-toolchain.toml`, `.tool-versions`, `mise.toml` and `.mise.toml`, at any depth.

**What makes a run partial.** Two things do:

- **The caller's arguments select tests.** That includes test name filters, `--skip`, `--ignored`, packages (`-p`, `--exclude`), targets (`--lib`, `--bins`, `--test`, `--doc` and the like), nextest filtersets (`-E`), `--partition` and `--run-ignored only` (`CargoCoverage.narrowed/1`). Such a run reports the tests it ran in `only_test_identifiers`, as percent-encoded `Module/Suite/name`. A test without a suite reads `Module//name`. `--skip` narrows instead of filling `skip_test_identifiers` because Cargo doesn't name the tests a filter left out.
- **A failure stopped the run**, under Cargo's and nextest's default fail-fast. `--no-fail-fast` and `--max-fail=all` keep the run whole.

Tuist's own selections never make a run partial: a shard's share, and tests quarantined as skipped, are left unreported, as for Mix. Each shard is a full run, and together the shards measure what an unsharded run does. Only plain `cargo test` applies quarantine. A nextest shard extracts its archive into the session, so `llvm-cov` can still read the binaries after the run. The archive's coverage maps name the paths of the checkout that built it, so the client maps them to the worker's checkout through the archive's package list before resolving them. The archive's build (`tuist cargo test-build`) is instrumented when coverage is on, so turn coverage on for the build and for its shards.

`tuist cargo coverage-complete [--commit <sha>]` signals that a commit's pipeline finished (step 4), as `tuist coverage complete` does. The command exists because the Linux CLI, where Rust's CI usually runs, has no `tuist coverage`. It reads the commit from the checkout, or from the CI provider on a pull request's merge checkout.

Every Cargo test run reports `coverage_enabled`, which is `false` when coverage is off. A run with coverage on also publishes the commit's Git history and file listing (`GitHistoryService`, as `tuist test` does) and each file's Git blob.

Cargo has no binary cache and no selective-testing hashes, so `uninstrumented_code` and hash-carried targets (`coverage_target_sources`) never apply.

**Instrumenting only the repository.** Like Xcode, which instruments only the targets whose coverage it gathers, and Bazel's `--instrumentation_filter`, Tuist's compiler hook adds `-C instrument-coverage` only to the libraries, binaries and test harnesses of crates inside the repository. Dependencies compile exactly as in a plain build, so they keep one set of outputs, unit-cache entries and compilation-cache entries for both kinds of run. Cargo can't see a flag the hook adds, so each instrumented crate's outputs carry a marker. Before Cargo starts, a run sets the repository's crates built as the other variant aside in the profile's `.tuist-coverage` directory, together with their Cargo fingerprints, and moves back the variant it wants when one was set aside (`CargoCoverage.reconcile`). Cargo then judges the restored variant with its own fingerprints, so a source edited or a dependency rebuilt in the meantime still rebuilds it, and switching between plain and coverage runs rebuilds nothing otherwise. When a custom `rustc-wrapper` keeps the hook out, the flag goes to `build.rustflags` for every crate instead. Limitations:

- With a custom `rustc-wrapper`, target-specific `rustflags` in a Cargo configuration file replace the flag Tuist adds to `build.rustflags`. Such a project adds `-C instrument-coverage` to them itself. A run whose tests wrote no profiles says so.
- Plain `cargo` commands run outside Tuist after a coverage run reuse the instrumented crates until `tuist cargo` switches them back.
- Unit tests in a source file's `#[cfg(test)]` module are part of that file, so their lines count as the file's code, as `llvm-cov` and `cargo llvm-cov` count them.
- Tests that start other processes, such as the tool binary through `CARGO_BIN_EXE_*`, count their children in the `run` scope only when the children are instrumented, and in no evidence scope.
