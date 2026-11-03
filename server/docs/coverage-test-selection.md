# Coverage-based test selection

How Tuist skips the tests a change can't affect, using the per-test coverage evidence earlier runs recorded. Users see it as selective testing's coverage strategy; the code calls it test impact analysis (`Tuist.TestImpactAnalysis` on the server, `TestImpact*` in the CLI). It's in early access behind `Tuist.FeatureFlags.test_impact_analysis_enabled?/3` (see [Enabling it](#enabling-it)). It builds on the evidence described in [Code coverage](code-coverage.md).

**The invariant.** Coverage evidence only ever removes tests from what default selective testing would run, never adds to it, so off the default branch a coverage run never runs more than a default run. Within that, anything Tuist can't prove unaffected runs: new tests, tests without evidence, and every test whenever selection can't be computed. When coverage can't decide, the run is a plain selective testing run.

The server side (baselines, the rule pipeline, impact runs and their shards, storage, the API, the UI and the flag) is shared by every build system, and everything before [Xcode](#xcode) describes it in build-system terms. Each build system plugs in through the [hooks](#build-system-hooks) below. Only Xcode selects today; Gradle, Mix and Cargo would supply the same hooks.

## Build-system hooks

| Hook | What the build system supplies | Xcode |
| --- | --- | --- |
| **Prune before asking** | Its own default selective testing, run first: what it already skips stays skipped, and coverage only decides what's left. When nothing is left, no request is made (except on the default branch). | [Test target hashes](#pruning-during-generation) |
| **Evidence granularity** | Which tests get test-scoped evidence. Tests without it always run (`no_evidence`), so a build system with module-level evidence only can only skip by its own pruning. | [XCTest and XCUITest only](#evidence-and-swift-testing) |
| **Scope** | Its block in the requests (`xcode`, …): what the invocation tests, and the key a baseline's measured set must have run whole. | [Scheme, test plan, destination](#scope-and-platform) |
| **Platform key** | One coarse value per run, recorded on every coverage upload (`coverage_runs.platform`) and sent in the baseline request. | [`XcodeGraph.Platform`](#scope-and-platform) |
| **Tracked files** | The files whose change can affect any test without showing in coverage. | [Manifests, pins, build settings](#tracked-files) |
| **Affected modules** | Per changed file, the test modules that depend on the module owning it, from its own graph. | [`TestImpactAffectedModules`](#the-diff-and-affected-modules) |
| **Applying skips** | How it turns the [skip list](#the-skip-list) into its own filters, for whole modules and single tests. | [Pruning, `-skip-testing`, the skip file](#applying-skips) |

## Enabling it

The server decides whether a project selects: `Tuist.FeatureFlags.test_impact_analysis_enabled?/3` requires coverage for the project (`coverage_enabled?/3`) and the `:test_impact_analysis` account flag. Like `:xcode_coverage`, the flag needs an explicit toggle on canary and production and is on everywhere else. `test_impact_analysis_account_enabled?/2` is its per-account side, which `Tuist.Ops.FeatureFlags` reports. It's a separate flag from `:xcode_coverage` because some accounts already have coverage, and `coverage_enabled?/3` is always true for Mix projects.

When the project isn't enabled, the baseline request answers `not_enabled`, the client runs default selective testing without deepening, diffing or calling the runs endpoint, and nothing is stored. The runs endpoint answers 404, and the Test Selection sidebar item is hidden.

## Concepts

| Concept | What it is |
| --- | --- |
| **Baseline** | The nearest ancestor of the checked-out commit with a full run of the requested scope on the same platform, within the evidence window. See [Baselines](#baselines). |
| **Evidence window** | The checked-out commit's ancestors back to the baseline. Commits without coverage are walked but not counted; at most 20 commits with coverage, the baseline included, may sit in it. A test's evidence is the newest of its versions from a commit in the window, through the same lookup coverage carry uses. |
| **Diff** | The changed files between the baseline and the commit that is actually checked out, with each file's status, blob and affected test modules: at most 5,000 entries plus the total count. Keyed by checked-out commit and baseline, so it's computed once and reused by every invocation on that commit. A dirty checkout's diff is never stored. |
| **Impact run** | The decision for one test invocation: the diff, the scope, the requested modules, the outcome and reason, the rule trace and the counts. Fallbacks are recorded too. It knows nothing about shards: a shard plan points to it. A retried invocation creates a new one. |
| **Selected tests** | One row per test that will run, with the rule that selected it and the matched path. They record intent; `test_case_runs` records the outcome. Skipped tests are never stored: they're the baseline's tests in scope minus the selected ones. |

## How the data flows

Only for the coverage strategy. Default selective testing keeps its own flow and creates no impact run.

The decision is made once per invocation, before the build: in the plan job for sharded runs and in the single job otherwise. Shards make no impact-analysis calls and need no Git history.

1. **Prune.** The client runs its default selective testing and keeps the modules it left to decide.
2. **Baseline.** `POST …/tests/selective-testing/coverage/baseline` with the checked-out commit, the platform and the build system's scope block. When the checkout is GitHub's synthetic merge commit, the client also sends its two parents (`parent_shas`: the pull request head and the base-branch tip), which the server's history has. The response is `baseline_sha` and whether the diff for that commit and baseline is already stored (`diff_cached`), or `null` with a reason.
3. **Diff**, only with a baseline and only when it isn't cached or the checkout is dirty. The client deepens a shallow clone until the baseline is reachable, diffs the baseline against the checked-out commit, not the pull request head, reading only trees, and adds dirty and untracked files. Each changed file is tagged with the test modules it can affect. History that can't be reached within the client's budget is `history_unavailable`.
4. **Runs.** `POST …/tests/selective-testing/coverage/runs`, synchronous, with a 2 s timeout: the scope, the modules left to decide, and either the baseline (plus the diff when step 2 asked for it) or the reason there's none. The server records an impact run and returns its `id`, the `outcome` (`selected` or `fallback`), the `reason` and `matched_path` of a fallback, the counts, and on `selected` the skip list. A timeout or an error means a fallback on the client, with a warning and no impact run.
5. **Act on the outcome** (see [The outcome on the client](#the-outcome-on-the-client)).
6. **Plan shards** (sharded runs only), after the build as today: `POST …/tests/shards` with `test_impact_run_id` when the outcome was `selected`. The server plans the suites that have selected tests, at suite granularity. Without the ID it plans as today.
7. **Read a shard** (sharded runs only), by reference and index as today. For a plan that points to an impact run, the response also carries `test_impact_skip`, the shard's skip list.
8. **Run** with the skip list applied, through the build system's own filters.
9. **Upload** as today, plus `test_impact_run_id` on `POST …/tests`, on fallbacks too, sharded or not. It's stored on the test run, which is how the run page finds its impact run.

### The default branch never selects

On the project's default branch, the baseline request still goes out (it's how the client learns whether the project is enabled), and the runs request carries `fallback_reason: excluded_branch`. The server decides the same from `git_branch == project.default_branch`. Either way the client runs every test in scope, including what its own pruning would skip, so each default-branch commit with a run is a full run with fresh evidence, and a pull request's window usually ends at its merge base.

### The outcome on the client

| Outcome | What runs | Why |
| --- | --- | --- |
| `selected` | What pruning left, minus the skip list | Modules with nothing selected aren't built at all where the build system can avoid it |
| `excluded_branch`, `no_baseline`, `baseline_too_old`, `diff_too_large` | Every test in scope, including what pruning would skip | The commit becomes the next baseline |
| Any other fallback, `not_enabled`, a failed or timed-out request | What pruning left | Exactly a default run |

What a user excluded explicitly (a flag that drops a kind of test, say) stays excluded in the second row. The client sends the impact run's ID with every test upload of the invocation, and with the shard plan only on `selected`.

## Baselines

`Tuist.TestImpactAnalysis.Baselines.resolve/3` walks the commit graph (`Tuist.GitHistory.ancestors/3`) from the checked-out commit, or from the parents the client sent when the server's history doesn't have it, nearest first, reading the project's `coverage_commits` beside it. It walks a little deeper each time (64, 256, 1,024 commits, then the history window), so the common case reads a few dozen commits.

A commit is a baseline when it has a **full run**, a run at the commit that:

- ran the requested scope, which the commit's measured set lists as run whole (`schemes`, not `partial_schemes`; a request without a scheme accepts any commit whose measured set lists one);
- ran it whole: its `coverage_runs` row isn't `partial`, so no filter narrowed it and every shard reported;
- ran on the requested platform (`coverage_runs.platform`);
- uploaded test-scoped evidence (`coverage_files` rows with `scope_kind = 'test'`).

A commit's measured set is only written once its runs' coverage is folded, so a run still being processed isn't eligible yet. The baseline isn't gated on `coverage_commits.complete`, which only exists where the pipeline runs `tuist coverage complete`.

| Result | When |
| --- | --- |
| The baseline, with its full runs (`run_ids`) and the window's commits (`window_shas`) | A full run with evidence within 20 commits with coverage |
| `no_baseline_evidence` | A full run within the window would be the baseline, but uploaded no test-scoped evidence |
| `baseline_too_old` | The nearest full run is more than 20 commits with coverage back |
| `no_baseline` | No full run on the platform in the history window, or the history has neither the checked-out commit nor its parents |

The runs request resolves the same baseline again (`baseline_sha:` fixed) to rebuild the window, and records the baseline's runs on the impact run (`baseline_run_ids`), so every shard read later derives its skip list from the tests the decision saw.

- **Platform, not OS version.** The same test can execute different files on two platforms, so a baseline must match the request's platform key. CI pipelines almost always test one platform per invocation, and projects that test several run each in its own job at the same commit, so each finds a same-platform baseline. OS versions of one platform mostly change over time, as toolchains are upgraded: matching them would leave runs without a baseline after every upgrade. Coverage uploaded with an empty platform never serves as a baseline for a request that names one.
- **Evidence is per commit, not per scope.** A test is identified by module, suite and name. Its evidence is the union across every scope that ran it, which can only select more. The requested scope still has to be one the baseline commit ran whole.
- **A window over the cap starts a new baseline.** `no_baseline` and `baseline_too_old` run every test in scope, and the commit becomes the next baseline. A long branch with a run on every commit runs everything about once every 20 measured commits.
- **A large diff runs everything.** Above 5,000 changed files the run records `diff_too_large`, runs every test in scope, and its commit becomes a baseline.
- **Every run refreshes evidence.** Every run uploads test-scoped evidence for the tests it executed, so newer commits in the window can use it. Skipped tests write nothing. Evidence expires with coverage retention (`TUIST_COVERAGE_FILE_RETENTION_DAYS`, 90 days by default), and a test whose versions all expired runs as `no_evidence`. There's no required nightly run: the default branch's runs are the baselines.

## Impact analysis rules

Selection is a pipeline of rules (`Tuist.TestImpactAnalysis.Rule`) run in a fixed order by `Tuist.TestImpactAnalysis.run/1` over one shared, read-only input. New behaviour is a new rule, not a new branch in one large function.

- **Input** (`Tuist.TestImpactAnalysis.Input`, built once per request by `load/2`): the tests in scope (the baseline runs' tests in the requested modules, `baseline_tests/3`), the changed files, the tracked-file globs, the baseline's blobs, each test's versions in the window (`Tuist.Tests.Coverage.TestSources.versions/4` with `shas:`), per-module target-level evidence, the baseline's test files and the flaky tests. `new/1` resolves each test's versions against the checkout's blobs (the baseline's listing, `GitHistory.blobs_at/3`, overlaid with the blobs of the changed files) through `TestSources.resolve/2`, the lookup coverage carry shares, and indexes the result so rules asking the same question share one answer.
- **State** (`Tuist.TestImpactAnalysis.State`): every test starts undecided. A rule can select or skip an undecided test with its own name as the reason. A decided test is final, so the first rule that decides a test is its reason and no later rule can undo a selection.
- **Verdict**: `:continue` runs the next rule; `:done` stops and keeps the decisions; `{:abort, reason, matched_path}` discards every decision and makes the outcome `fallback`.
- **End of pipeline**: tests still undecided are selected with reason `undecided`. A test is only skipped when a rule explicitly skips it, so a missing rule or an early `:done` can only select more.
- **Rules are pure.** They do no writes and no reads of their own, so each is tested alone with a hand-built input, and the same input always gives the same decisions.
- **The order is code, versioned.** The rule list lives on the server, not in a manifest. Each impact run stores `rules_version` (bump `@rules_version` when a rule's behaviour or the order changes) and a `rule_trace`: per rule that ran, how many tests it selected and skipped and its verdict.

The baseline isn't a rule: it's resolved before the pipeline, and a run without one records a fallback and skips the pipeline. `diff_too_large` isn't a rule either: `Tuist.TestImpactAnalysis.Runs` checks the count before the input is loaded.

| # | Rule (`Rules.*`) | Decides | Verdict |
| --- | --- | --- | --- |
| 1 | `tracked_files` (`TrackedFiles`) | Nothing. Checks the changed paths against the project's tracked files (`GitHistory.settings(project).tracked_file_globs`), whose change can affect any test without showing in coverage. | Abort with `tracked_file_changed` and the first matching path; otherwise continue |
| 2 | `test_file_changed` (`TestFileChanged`) | Selects every test of each suite a changed test file belongs to, whether or not that test's own evidence includes it. A test file is one the baseline recorded as test code; its suites are those whose tests' newest versions include it (which holds what the suite's setup ran). `matched_path` is the file. | Continue |
| 3 | `failed_last_run` (`FailedLastRun`) | Selects tests whose newest version in the window failed, or comes from a run where they were flaky. | Continue |
| 4 | `no_evidence` (`NoEvidence`) | Selects tests without a test-scoped version in the window: a new test or module, a test the build system records no per-test evidence for, another platform, or expired evidence. | Continue |
| 5 | `impacted` (`Impacted`) | Selects tests the checkout reproduces none of their versions for: a file the test or its suite's setup executed has a different blob now. A module whose target-level evidence (what its test processes ran outside any test, such as an app's launch) includes a changed path selects all its tests. `matched_path` is the first changed path the newest version or the target evidence includes. | Continue |
| 6 | `owned_without_evidence` (`OwnedWithoutEvidence`) | Selects every test in the `affected_modules` of each changed file no evidence includes: a resource, a new file, or a declarations-only file. A file no module owns (empty list) or the client couldn't classify (absent) selects nothing. | Continue |
| 7 | `unaffected` (`Unaffected`) | Skips every test still undecided. | Done |

**Tracked files are the coverage carry list.** Rule 1 reads the setting coverage carry already stops at, so a test selection skips gets carried coverage, and a commit where carry stops makes selection fall back. A narrower list would skip tests whose coverage then shows as unknown; a wider one would fall back for no reason. The list is the same for every build system today, and its defaults are Xcode's (see [Tracked files](#tracked-files)).

**Affected modules come from the client's graph.** For each changed file the client lists the test modules that depend, directly or not, on the module that owns it. An empty list means no module owns the file (a README, CI configuration); absent (`nil`) means the graph can't attribute it to one module, and those files should be tracked files instead.

## The skip list

The server sends a skip list of `{module, suite?, name?}` entries (`TestImpactSkippedTest`; `Runs.skip_entries/2` unsharded, `Runs.shard_skip/4` per shard): the tests in scope that weren't selected. Each build system turns it into its own filters.

- A test the server doesn't know, such as one added in the change, isn't on it and runs, which keeps the invariant.
- Tests are never collapsed into a suite, because a suite can gain tests the server hasn't seen.
- A module is one `{module}` entry only when none of its tests is selected, which rules 2 and 6 rule out for any module whose test files or owned files changed.
- `{module, suite}` entries appear only in the catch-all shard's list, for the other shards' suites.
- The skip list is never stored: it's most of the suite, and it's derived from the baseline's tests and the selected rows per request.

## Sharding

- **Selection and planning are separate calls.** The runs call writes the selected tests before the build; `POST …/tests/shards` plans them after it, as today. A plan points to its impact run (`shard_plans.test_impact_run_id`); the impact run holds no shard information, so fallbacks need no second planning path.
- **Plans are per suite.** A coverage plan holds only the suites with selected tests (`Runs.shard_units/2`), stored in `shard_plan_test_suites` like any suite plan, and each shard's selected tests stay in `test_impact_run_tests`. Nothing is stored twice.
- **Shards are balanced on what will run**: each suite is priced at its selected tests' `test_cases.avg_duration`, a test without one counting as the median of those with one. Skipped work can lower the shard count.
- **Each shard's skip list is narrowed to its work.** A regular shard runs only its suites and skips the unselected tests inside them. The catch-all shard keeps its role of running every suite no other shard owns, so new suites still run; its list adds the modules with nothing selected, the other shards' suites, and the unselected tests everywhere else.
- **Shards can't disagree.** The decision is fixed before planning, and a shard reads the same plan, selected rows and `baseline_run_ids`. Re-running failed shards gets the same run; re-running the whole workflow gets a new plan and impact run.
- Immutable shard plans (reporting version 1) drop coverage at ingest, so sharded runs on them never become baselines.

## Fallbacks

Selection fails open to default selective testing, as the quarantine fetch does. Fallback reasons are plain strings, never enums, so the server can add one without breaking older clients, which treat an unknown outcome as a fallback.

| Situation | Result |
| --- | --- |
| The run is on the default branch | `excluded_branch`: every test in scope runs |
| No full run in reach, or none on the requested platform | `no_baseline`, from the baseline request: every test in scope runs |
| The nearest full run is more than 20 commits with coverage back | `baseline_too_old`, from the baseline request: every test in scope runs |
| More than 5,000 changed files | `diff_too_large`: every test in scope runs |
| The baseline has no test-scoped evidence | `no_baseline_evidence`, from the baseline request: default selective testing |
| A tracked file changed | `tracked_file_changed` with the path, from rule 1: default selective testing |
| Deepening didn't reach the baseline within its budget | `history_unavailable`, sent by the client: default selective testing |
| The stored diff vanished, or a dirty checkout sent no changed files | `diff_unavailable`: default selective testing |
| The project or account isn't enabled | `not_enabled`, from the baseline request: default selective testing, nothing stored |
| A request timed out or failed | Default selective testing on the client, with a warning and no impact run |
| Dirty or untracked files | Selection still runs, with a diff that isn't stored |

There's no separate accuracy measurement. Default-branch runs are the safety net: a test coverage skipped on a branch that breaks shows up as a regular failure once the change reaches the default branch.

## API

Both endpoints are in `TuistWeb.API.SelectiveTestingCoverageController`, under `/api/projects/{account}/{project}/tests/selective-testing/coverage`, beside the existing `/tests/coverage`, `/tests/shards` and `/tests/git-history`. Paths name the strategy, so another strategy gets its own segment beside `coverage`.

| Operation | Request | Response |
| --- | --- | --- |
| `POST …/baseline` (`resolveTestImpactBaseline`) | `build_system`, `commit_sha` (required); `parent_shas`, `platform`, the build system's block (`xcode`) | `TestImpactBaseline`: `baseline_sha` (nullable), `reason`, `diff_cached` |
| `POST …/runs` (`createTestImpactRun`) | `build_system`, `head_sha` (required); `commit_sha` (defaults to `head_sha`, keys the diff), `parent_shas`, `baseline_sha` or `fallback_reason`, `changed_files [{path, status, blob?, affected_modules?}]` with `changed_files_count`, `dirty`, `modules`, `platform`, `git_branch`, the build system's block | `TestImpactRun`: `id`, `outcome`; `reason` and `matched_path` on a fallback; `counts {requested, selected, skipped}` and `skip [TestImpactSkippedTest]` on `selected` |
| `POST …/tests/shards` (`createShardPlan`) | gains optional `test_impact_run_id` | unchanged |
| `GET …/tests/shards/{reference}/{index}` (`getShard`) | unchanged | gains `test_impact_skip [TestImpactSkippedTest]` for a plan that points to an impact run |
| `POST …/tests` (`createTest`) | gains optional `test_impact_run_id` | unchanged |

`TestImpactSkippedTest` is `{module, suite?, name?}`, named the same way for every build system. The shard read's list is `test_impact_skip` because the read already has `skip`, the catch-all's identifiers as strings. The runs response includes `skip` on every `selected` outcome; sharded clients ignore it and read their shard's list.

- **Required stays minimal.** Only what every build system has is required. A required field can't become optional without breaking generated clients.
- **One block per build system.** Xcode's scope goes in `xcode`; Gradle, Mix and Cargo get their own blocks when they need fields. A field moves to the top level only once a second build system needs it.
- **New fields are optional**, with a default that keeps today's behaviour. **Values that will grow are strings, not enums**: the CLI's generated client turns enums into frozen Swift enums, so an unknown value would fail decoding.

## Storage

Impact runs live in ClickHouse next to `shard_plans`, written and read back the same way (`Tuist.TestImpactAnalysis.Storage`: IngestRepo with a retried read), so one plan never spans two databases. The tuples are positional, since the `ch` driver drops element names from the types it inserts with.

| Table | What it holds | Retention |
| --- | --- | --- |
| `test_impact_diffs` (`Tuist.TestImpactAnalysis.Diff`) | One row per project, checked-out commit and baseline (`ReplacingMergeTree`, so identical concurrent writes collapse): `changed_files` as `(path, status, blob, affected_modules)`, at most 5,000, and `changed_files_count`. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90) |
| `test_impact_runs` (`Tuist.TestImpactAnalysis.Run`) | One row per invocation, fallbacks included: `head_sha`, `commit_sha`, `baseline_sha`, `baseline_run_ids`, `git_branch`, `dirty`, `strategy`, `build_system`, `platform`, `build_context` (the scope block's fields, each capped at 1,024 characters), `requested_modules`, `outcome`, `reason`, `matched_path`, `rules_version`, `rule_trace` as `(rule, selected, skipped, verdict)`, and the counts. Ordered `(project_id, inserted_at, id)` for the overview's range read, with a bloom filter on `id` for the run page. | `TUIST_COVERAGE_RUN_RETENTION_DAYS` (365) |
| `test_impact_run_tests` (`Tuist.TestImpactAnalysis.RunTest`) | One row per selected test: `test_case_id`, `module_name`, `suite_name` and `name` (copied so a shard reads its suites by prefix and the client builds identifiers without a join), `reason` and `matched_path`. Ordered `(project_id, test_impact_run_id, module_name, suite_name, name)`. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90) |
| `coverage_runs.platform` | The platform each coverage run tested, for baseline matching. | With `coverage_runs` |
| `shard_plans.test_impact_run_id` | The impact run a coverage plan distributes. | With `shard_plans` |
| `test_runs.test_impact_run_id` | The impact run of the invocation, set at ingest like `shard_plan_id` (also on `shard_test_reports` and the summary views built over them). | With `test_runs` |

- **The link sits on the test run**, not the impact run, because the impact run is written before any test run exists. Linking it the other way would mean updating a ClickHouse row after upload, and an impact run whose build fails would never get one. `test_runs` has no TTL, so an old test run can keep an ID whose impact run expired; its tab then says so.
- **Retention.** Diffs and selected tests are built from file-level evidence and can't be explained once it expires, so they share its retention; runs keep the overview's statistics for as long as coverage run totals. All three tables are in `Tuist.Tests.Coverage`'s retention tables, so `mix tuist.coverage.retention` re-applies a changed setting.
- **Evidence isn't copied.** Test evidence comes from `coverage_test_sources` and target evidence from the baseline runs' `coverage_files` rows, both written by coverage. Selection adds no index, worker or backfill of its own.
- These are stored customer data: `server/data-export.md` documents them.

## UI

Users see "Test Selection" in navigation and "Selective Testing" as the run page tab, which already exists for default selective testing. `Tuist.Tests.Selections` holds the reads.

| Where | What it shows | Data |
| --- | --- | --- |
| Sidebar | "Test Selection" under Tests, when `test_impact_analysis_enabled?/3` | |
| Test Selection page (`TuistWeb.TestSelectionsLive`, `/tests/test-selection`) | The period's selected and skipped tests, skip rate and runs, with trends; a Runs tab (one row per impact run, opening its test run's Selective Testing tab) and a Baselines tab (default-branch commits that measured coverage and whether each can serve as one) | `test_impact_runs` in the range, joined to their test runs by `test_impact_run_id` |
| Test run page, Selective Testing tab (`TuistWeb.TestSelection.RunTab`) | Outcome, baseline, counts and invocation, then the Tests, Modules, Changed files, Shards (for a sharded run) and Configuration sub-tabs. A fallback shows the outcome and Configuration only. The tab shows for a run with a `test_impact_run_id`, also once the impact run expired, or when the run has default selective testing data. | The run's impact run |
| &nbsp;&nbsp;Tests | Every test coverage decided, its decision and the rule, its shard and outcome, filterable; selected tests that never reported are flagged | Selected tests from `test_impact_run_tests`; skipped ones are the baseline's tests in scope minus those, with reason `unaffected` |
| &nbsp;&nbsp;Modules | Per module, what decided it: default selective testing or coverage, with tests selected and skipped | The Tests rows grouped by module, plus the build system's pruning data (Xcode's `xcode_targets.selective_testing_hit`) |
| &nbsp;&nbsp;Changed files | Path and status, whether it's a tracked file, and how many tests it selected | `test_impact_diffs` and `matched_path` |
| &nbsp;&nbsp;Configuration | Rules version, rule trace and tracked files | `test_impact_runs` |
| Test case run page, Selective Testing tab (`TuistWeb.TestSelection.TestCaseRunTab`, `?tab=selective-testing`) | Why the test ran (rule, matched path), its shard, and the files the baseline's evidence says it executed, the changed ones first | The run's `test_impact_run_tests` row and the baseline's `coverage_files` evidence |

## Known limits

- Evidence records what ran, so it can't see compile-time dependencies (a changed macro, a constant folded at compile time). Inside modules pruning left, rule 6 catches files no evidence includes, but not a file that some test executed and another depends on only at compile time.
- Inputs outside the project graph and the tracked files (scripts, test data loaded from outside the project, toolchain files) are invisible to both evidence and the graph.
- The window cap (20 commits with coverage), the excluded branch (only the default branch) and the tracked-file list are fixed. Project-specific settings would be configured in the project's Tuist configuration: tracked files under coverage, since carry stops at them too, and excluded branches and the window cap on the strategy.
- Only Xcode selects. Another build system would send the same requests with its own block and supply the [hooks](#build-system-hooks).

## Decided against

- **Coverage instead of the build system's own pruning, falling back to it.** Coverage then had to decide the tests it has no evidence for: always running them made modules without per-test evidence run more than today, and letting the server consult the pruning could still run more when a flaky test pulled a pruned module back in. Pruning first keeps the coverage strategy a strict improvement on the default.
- **A named default strategy, a "none" strategy, or environment overrides.** Leaving the strategy out already means the default, and the existing switch for selective testing already turns selection off; a second way to say either could disagree with the first.
- **Platform-aware evidence.** Recording the exact device and OS version on each test's evidence would let another platform's baseline serve, but a same-platform baseline is nearly always there.
- **Dry-run, shadow or comparison modes.** They add flags, columns and a scoring pipeline; full runs on the default branch remain the safety net.
- **Diffing full file listings on the server.** The payload grows with the repository and large listings are truncated by `commit_file_limit`. The client diff sends only what changed.
- **Caching verdicts per commit.** Verdicts depend on evidence in the window, which can still arrive after the first run, and on the rules version. Only the diff is per commit.
- **A per-baseline path index.** It would copy the test-scoped evidence a second time and need a worker and a backfill; `coverage_test_sources` already holds what each test version executed.
- **A `target_changed` rule.** A module's hash includes transitive sources, so it would select nearly everything with evidence. Tests without evidence already run as `no_evidence`.
- **Planning shards in the runs call.** It tied the impact run to sharding settings and needed a second planning path for fallbacks.
- **An idempotency key on impact runs.** ClickHouse can't enforce uniqueness, and shards already reach the run through the newest plan for their reference.
- **Storing the skip list, or collapsing it into suites.** It's most of the suite, and a suite can gain a test the server doesn't know, which would then be skipped.

## Xcode

### Configuration

One optional strategy per project, in `Tuist.swift` next to the coverage option:

```swift
let tuist = Tuist(
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage()) // omit strategy for the default
    ),
    project: .tuist()
)
```

| Strategy | What it skips | Decided by | Granularity |
| --- | --- | --- | --- |
| none (default) | Test targets whose hash already passed | The CLI, locally | Test target |
| `.coverage()` | What the default skips, then, in the targets left, the tests whose baseline evidence touches no changed file | The CLI for target hashes, then the server, before the build | Test target, then test case |

- **`.coverage()` runs on top of the default.** The CLI hashes and prunes test targets as today, and coverage decides the tests in the targets left. What coverage can't decide per test (Swift Testing tests, targets without TestCoverageAttribution) keeps today's target-level behaviour.
- **The strategy is optional.** `.selectiveTesting(strategy: Strategy? = nil)` and `.testInsights(selectiveTesting: SelectiveTesting? = nil)`; `nil` means default selective testing. `Strategy` is a struct with static constructors, like `TestInsights.Coverage`, not an enum: adding a parameter to an enum case breaks every manifest that wrote `.coverage`, while a new defaulted parameter on `.coverage(…)` doesn't.
- **It requires coverage uploads.** The loader rejects `.coverage()` with `coverage: .coverage(upload: false)` (`ConfigManifestMapperError.coverageStrategyRequiresCoverageUpload`).
- **Test targets must link [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 or later**, which records per-test evidence and reads the skip file (see [Applying skips](#applying-skips)). The manifest can't check this: a target without it has no test-scoped evidence, so its tests always run (`no_evidence`) and it's only ever skipped whole by its hash.
- **Turning it off** is the existing `--no-selective-testing` (`TUIST_TEST_SELECTIVE_TESTING`): nothing is skipped and no impact run is created. There's no other flag, environment variable or manifest value for "off".

### Pruning during generation

Selection runs only under `tuist test`, inside project generation. `TestsCacheGraphMapper` tags the test targets whose hash already passed as prunable, as today, and `TestImpactGraphMapper` runs right after it, before anything is pruned. It asks `TestImpactSelector.current` (set by `TestService` for the invocation) to decide the test targets hashing left. When every target's hash matched, nothing is left and no request is made, except on the default branch. `TestImpactGraphMapper` is registered in the binary cache's graph mapper factory, so it needs a CLI built with the cache. Pruning has to happen there because `xcodebuild test -skip-testing:X` still builds X. `tuist xcodebuild test` doesn't select, and `test-without-building` reads the selection a previous build persisted in the run metadata (`RunMetadataStorage.testImpactSkip`).

The CLI reads the project's default branch from `GET /api/projects/{handle}` when the run isn't for a pull request, and sends `excluded_branch` on it.

What each outcome does to the generated graph (`TestImpactGraphDecision`):

| Outcome | Graph |
| --- | --- |
| `selected` | Modules with no selected test are pruned (`prune`), so they aren't built at all |
| `excluded_branch`, `no_baseline`, `baseline_too_old`, `diff_too_large` | Every test target in scope runs, hash hits included (`runAll`) |
| Any other fallback, `not_enabled`, a failed or timed-out request | As hashing left it (`unchanged`) |

`TestImpactSelector.runAllReasons` holds the reasons in the second row. A target `--skip-ui-tests` or something else made prunable before hashing stays pruned under `runAll`.

**The impact run's ID** goes into `RunMetadataStorage.testImpactRunId`, so every `createTest` of the invocation sends `test_impact_run_id`. The shard plan gets it only on `selected`.

**Output.** The CLI prints the targets hashing skipped, as today, then coverage's counts (`Coverage-based test selection: N selected, M skipped, of R tests`) and the modules with nothing selected, or the fallback reason and matched path.

The CLI's clients are `ResolveTestImpactBaselineService` and `CreateTestImpactRunService` in TuistServer. Neither throws: each has a 2 s timeout and maps every failure to a fallback.

### Scope and platform

- **Scope.** The `xcode` block carries the scheme, test plan and destination. The scheme is what a baseline commit's measured set must list as run whole, and the impact run keeps the three as its `build_context`. Any `-only-testing` or `-skip-testing` narrowing (quarantined tests aside) marks a run `partial`, as described in [Code coverage](code-coverage.md#xcode).
- **Platform.** The CLI records the platform on every coverage upload as an `XcodeGraph.Platform` raw value (`ios`, `macos`, …), read from the `-destination`, with simulators and devices folded together, and sends the same value in the baseline request. The OS version and the per-test destination aren't part of it: simulators and Xcode are upgraded over time. Server-processed coverage has an empty platform, so those runs never serve as a baseline for a request that names one.

### The diff and affected modules

The CLI deepens a shallow clone with `git fetch --filter=blob:none --deepen=<n>`, within `GitHistoryLimits.deepenBudgetSeconds`, until the baseline is reachable, then runs `git diff --raw --no-renames <baseline>` against the checked-out commit and adds dirty and untracked files. Only trees are read, never blobs.

`TestImpactAffectedModules` lists each changed file's affected test modules from the generated graph, or from XcodeGraphMapper for a plain Xcode project. Files the graph can't attribute to one target (`.xcconfig`, files inside the `.xcodeproj`) are sent without the list, and they're tracked files.

### Tracked files

`GitHistory`'s default `tracked_file_globs` are Xcode's inputs: dependency pins and manifests (`Package.resolved`, `Package.swift`, `Podfile.lock`, `Cartfile.resolved`), project generation (`Project.swift`, `Workspace.swift`, `Tuist.swift`, `Tuist/**`), build settings (`*.xcconfig`, `project.pbxproj`), test plans (`*.xctestplan`) and `.xcode-version`. `project.pbxproj` stays on the list because build settings live there, even though in a plain Xcode project it changes whenever a file is added or removed.

### Evidence and Swift Testing

Under `.coverage()`, Swift Testing tests keep today's target-based behaviour: their target is skipped when its hash matches, and otherwise they run.

- **Test-scoped evidence is XCTest and XCUITest only.** TestCoverageAttribution records no `test` or `suite` scope for Swift Testing (see [Code coverage](code-coverage.md#xcode)), so every Swift Testing test in a target left after hashing is selected by `no_evidence`. Swift Testing tests are therefore never on a skip list TestCoverageAttribution can't honour, and the server needn't know which framework a test uses. Nor is a target that doesn't link TestCoverageAttribution: its tests are all `no_evidence`.
- **The fallback is per target, not per run.** A scheme can list XCTest targets, Swift Testing targets and targets that mix both, even in one file, run in one test process. Target hashes decide first, coverage decides the XCTest tests in the targets left, and Swift Testing tests run whenever their target runs. In a mixed target the listed XCTest tests are removed, and the remaining XCTest tests and every Swift Testing test run.
- **Target-scoped evidence still covers Swift Testing**, from Xcode's raw profiles, so a Swift Testing target's code is part of rule 5's target-level check and carries with its whole target.
- **Why not per test.** A Swift Testing trait has no public way to skip a test, it would have to be added to every suite, and Swift Testing runs tests in parallel by default, which leaves overlapping tests without evidence.

### Applying skips

`TestImpactSkipList` turns the skip list into what xcodebuild receives:

| Entry | Unsharded | Sharded |
| --- | --- | --- |
| `{module}` | Pruned from the generated project during generation, so it isn't built or run | `-skip-testing:Module`, appended to the shard's `skip` |
| `{module, suite}` | Never sent | The catch-all shard's list of other shards' suites; already in its `skip`, so ignored |
| `{module, suite, name}` | The skip file | The skip file |

A regular shard runs its suites with `-only-testing`, as today.

**The skip file.** Single tests are removed in the test process. The CLI writes `module/suite/name` lines (`module` the test bundle name, `suite` the XCTest class without its Swift module, `name` as the result bundle names it, `testAdd()`) to a temporary file and sets `TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE` in xcodebuild's environment (`XcodeBuildEnvironment.additionalVariables`, the way `TEST_COVERAGE_ATTRIBUTION_DIR` is passed). xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the test process without the prefix, where TestCoverageAttribution 0.3.0 or later reads `TEST_COVERAGE_ATTRIBUTION_SKIP_FILE` and removes the listed XCTest tests from `+[XCTestCase defaultTestSuite]` before they run.

- A removed test is absent from the result bundle, and a class whose tests were all removed doesn't run its class `setUp`. The run page lists skipped tests from the impact run, so nothing is lost and no `test_case_runs` row needs telling apart from the project's own `XCTSkip`.
- It works with `test` and `test-without-building -xctestrun`, hosted unit tests and UI tests, serial and parallel clones, and test plans with their own environment. Every test bundle in the invocation reads the same file and keeps its own entries; lines for tests that don't exist and malformed lines are ignored, and an unreadable file skips nothing. Swift Testing tests are never skipped, even if listed.
- Only targets that link the package can skip single tests, which loses nothing: per-test evidence comes from the package, so a target without it has none and can only be skipped whole.
- Quarantine is unchanged: its skipped tests still go to `-skip-testing`.

**Why not xcodebuild's own options.** One `-skip-testing` per test hits `ARG_MAX` (1 MiB on macOS, arguments and environment together) at around 15,000 tests, and xcodebuild reads no argument file. The `.xctestrun`'s `SkipTestIdentifiers` can't skip single Swift Testing tests and would split `tuist test` into build-for-testing, an edit, and test-without-building.
