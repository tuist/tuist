# Coverage-based test selection

How Tuist skips the tests a change can't affect, using the per-test coverage evidence earlier runs recorded. Users see it as selective testing's coverage strategy; the code calls it test impact analysis (`Tuist.TestImpactAnalysis` on the server, `TestImpact*` in the CLI). It builds on the evidence described in [Code coverage](code-coverage.md).

**The invariant.** Coverage evidence only ever removes tests from what default selective testing would run, never adds to it, so off the default branch a coverage run never runs more than a default run. Within that, anything Tuist can't prove unaffected runs: new tests, tests without evidence, and every test whenever selection can't be computed. When coverage can't decide, the run is a plain selective testing run.

The document has two parts. The [shared model](#strategy) (baselines, the rule pipeline, impact runs and their shards, storage, the API, the UI and the flag) holds for every build system and is written in build-system terms; a build system plugs in through the [hooks](#what-each-build-system-supplies), though some shared code still reads Xcode's names (listed under the hooks). The [Xcode](#xcode) part describes what only the Xcode client and its evidence do. Only Xcode selects today; Gradle, Mix and Cargo get a part like it when their selection lands.

## Strategy

Coverage is a second strategy for selective testing, chosen per project in the build system's own configuration (Xcode's is under [Configuration](#configuration)). Leaving it out keeps default selective testing.

| Strategy | What it skips | Decided by | Granularity |
| --- | --- | --- | --- |
| none (default) | Test modules whose hash already passed | The client, locally | Test module |
| coverage | What the default skips, then, in the modules left, the tests whose baseline evidence touches no changed file | The client for module hashes, then the server, before the build | Test module, then test case |

- **Coverage runs on top of the default.** The client hashes and prunes test modules as today, and coverage decides the tests in the modules left. What coverage can't decide per test (tests without test-scoped evidence) keeps today's module-level behaviour. When every module's hash matched, nothing is left to decide: the client still records an impact run, with every module marked `skipped`, so its tests count as skipped, and the server records a selection of nothing without a diff or the rules.
- **Hash decisions are reported as today.** Each build system already reports its module hashes and hits with the run, also when selective testing is off, and the run page and coverage carry read them. The runs request doesn't repeat them; it only sends the modules left.
- **Turning it off** is the switch that already turns selective testing off for a run. There's no new flag or environment variable.
- **Test-scoped evidence is the prerequisite.** A baseline without it reports `no_baseline_evidence` and the run falls back to the default. Which tests record it is up to each build system.

### Enabling it

The server decides whether a project selects: `Tuist.FeatureFlags.test_impact_analysis_enabled?/3` requires coverage for the project (`coverage_enabled?/3`) and the `:test_impact_analysis` account flag. Like `:xcode_coverage`, the flag needs an explicit toggle on canary and production and is on everywhere else. `test_impact_analysis_account_enabled?/2` is its per-account side, which `Tuist.Ops.FeatureFlags` reports. It's a separate flag from `:xcode_coverage` because some accounts already have coverage, and `coverage_enabled?/3` is always true for Mix projects. No per-run flag turns it on: the project's configuration is the opt-in.

When the project isn't enabled, the baseline request answers `not_enabled`, the client runs default selective testing without deepening, diffing or calling the runs endpoint, and nothing is stored. The runs endpoint answers 404, and the Test Selection sidebar item is hidden.

### What each build system supplies

| Hook | What it is | Xcode |
| --- | --- | --- |
| **Configuration** | Where a project opts into the strategy. | [`Tuist.swift`](#configuration) |
| **Module hashing** | Which modules default selective testing prunes before coverage is asked, and where it reports hits. | [Test target hashes, `xcode_targets`](#rule-inputs-on-xcode) |
| **Test-scoped evidence** | Which tests record the files they executed. The rest fall to `no_evidence`. | [XCTest and XCUITest with TestCoverageAttribution](#swift-testing) |
| **Platform key** | What a baseline must match, recorded on every coverage upload (`coverage_runs.platform`) and sent in the baseline request. | [The destination's platform](#schemes-and-destinations) |
| **Build context** | Its block in the requests, stored for display. The block's scheme also picks which baselines qualify. | [`xcode`: scheme, test plan, destination](#schemes-and-destinations) |
| **Tracked files** | Files whose change falls back, shared with coverage carry. | [The server's defaults](#rule-inputs-on-xcode) |

**Not every hook is pluggable yet.** The shared code reads Xcode's names directly:

- **Build context and scope.** The server reads only the `xcode` block. `Runs` stores it as `build_context`, and `Storage` keeps only its `scheme`, `test_plan` and `destination`. `Runs` and the baseline endpoint pass its `scheme` to `Baselines`. The Test Selection page searches runs by that scheme or test plan, and the run tab finds the baseline's runs by that scheme. A request without an `xcode` block has no scheme, so any commit whose measured set lists a scheme can be its baseline.
- **Tracked files.** There's one server-wide list (`GitHistory.settings/1`'s `tracked_file_globs`, from configuration, with no per-project override) for every build system, and its defaults are Xcode's inputs. `build_system` picks nothing: it's stored on the impact run and shown on its Configuration sub-tab.
- **Module hashing.** The run tab's module-level hash data is Xcode's `xcode_targets` (see [UI](#ui)).

A second build system needs these turned into hooks first.
| **`affected_modules`** | Which test modules a changed file can affect, from a build graph. | [The generated graph or XcodeGraphMapper](#rule-inputs-on-xcode) |
| **Applying a skip list** | How whole modules and single tests are kept from running. | [Pruning, `-skip-testing` and a skip file](#applying-the-selection-on-xcode) |

## Naming

Users see selective testing, the name they already know, with coverage as its second strategy. "Selective testing" and "test selection" are umbrellas, since the default already selects tests and other strategies may follow, so paths name the strategy and code names the technique.

| Layer | Name |
| --- | --- |
| UI | "Test Selection" in navigation, and the run page's existing "Selective Testing" tab |
| API | `/api/projects/{account}/{project}/tests/selective-testing/coverage/…`: `POST …/baseline` and `POST …/runs`, beside `/tests/coverage`, `/tests/shards` and `/tests/git-history`. Another strategy gets its own segment beside `coverage`. |
| Server | `Tuist.TestImpactAnalysis`, with rules under `Tuist.TestImpactAnalysis.Rules`; the controller is `TuistWeb.API.SelectiveTestingCoverageController`, next to `SelectiveTestingTargetsController`; the UI's reads are in `Tuist.Tests.Selections` |
| ClickHouse | `test_impact_diffs`, `test_impact_runs`, `test_impact_run_tests`, and `test_impact_run_id` on `shard_plans` and `test_runs` |

The Xcode client's names are under [Configuration](#names-in-the-xcode-client).

## Concepts

| Concept | What it is |
| --- | --- |
| **Baseline** | The nearest ancestor of the checked-out commit with a full run of the requested scope on the same platform, within the evidence window. See [Baselines](#baselines). |
| **Evidence window** | The checked-out commit's ancestors back to the baseline. Commits without coverage are walked but not counted; at most 20 commits with coverage, the baseline included, may sit in it. It bounds only how far back the baseline can be, not which evidence counts. |
| **Evidence** | A test's evidence is its newest version the checkout reproduces: the files the test and its suite's setup executed, all with the blob they had then, on any branch and at any commit. `Tuist.Tests.Coverage.TestEvidence` is the one place coverage carry and selection get it from, so the two always agree; only the blobs they hand it differ. |
| **Diff** | The changed files between the baseline and the commit that is actually checked out, with each file's status, blob and affected test modules: at most 5,000 entries plus the total count. Keyed by checked-out commit and baseline, so it's computed once and reused by every invocation on that commit. A dirty checkout's diff is never stored. |
| **Impact run** | The decision for one test invocation: the diff, the build context, the requested modules, the outcome and reason, the rule trace and the counts. Fallbacks are recorded too. It knows nothing about shards: a shard plan points to it. A retried invocation creates a new one. |
| **Selected tests** | One row per test that will run, with the rule that selected it and the matched path. They record intent; `test_case_runs` records the outcome. Skipped tests are never stored: they're the baseline's tests in scope minus the selected ones. |

## Baselines

`Tuist.TestImpactAnalysis.Baselines.resolve/3` walks the commit graph (`Tuist.GitHistory.ancestors/3`) from the checked-out commit, or, when the server's history doesn't have it, from every parent and ancestor the client sent that the history has, nearest first. A known ancestor's distance from the checkout is its position in `ancestor_shas`: exact for linear history, approximate across merges. Ancestors the history lacks carry no coverage, so they never count toward the window. With none of them in the history the walk can't start, and the answer is `history_unknown`. The walk reads the project's `coverage_commits` beside it. It walks a little deeper each time (64, 256, 1,024 commits, then the history window), so the common case reads a few dozen commits.

A commit is a baseline when it has a **full run**, a run at the commit that:

- ran the requested scheme (`xcode.scheme`), which the commit's measured set lists in `schemes` and not in `partial_schemes`, and which the run's `coverage_runs.scheme` names (a request without a scheme accepts any commit whose measured set lists one, and any of its runs);
- ran it whole: its `coverage_runs` row isn't `partial`, so no filter narrowed it and every shard reported;
- ran on the requested platform (`coverage_runs.platform`; see [Scope and platform](#scope-and-platform));
- uploaded test-scoped evidence (`coverage_files` rows with `scope_kind = 'test'`). Not `coverage_test_sources`: it keeps one row per test version, naming that version's latest run, so once ClickHouse merges, a baseline's own rows can name a later run instead.

A commit's measured set is only written once its runs' coverage is folded, so a run still being processed isn't eligible yet. The baseline isn't gated on `coverage_commits.complete`, which only exists where the pipeline runs `tuist coverage complete`.

`Tuist.TestImpactAnalysis.Baselines` walks the commit graph itself instead of calling `Commits.nearest_measured_ancestor/5`, the search coverage's fold uses. That function returns a single commit, never the checked-out one, and filters only on what PostgreSQL holds (lines measured, a scheme in common). A baseline also has to pass ClickHouse checks (the run's platform, `partial` and test-scoped evidence), so the walk may have to look past the nearest measured commit. It also counts commits with coverage for the window, tells `baseline_too_old` from `no_baseline` and `no_baseline_evidence`, and starts from several commits at once (`parent_shas`, `ancestor_shas`).

| Result | When |
| --- | --- |
| The baseline, with its full runs (`run_ids`) and the window's commits (`window_shas`) | A full run with evidence within 20 commits with coverage |
| `no_baseline_evidence` | A full run within the window would be the baseline, but uploaded no test-scoped evidence |
| `baseline_too_old` | The nearest full run is more than 20 commits with coverage back |
| `history_unknown` | The history has none of the checked-out commit and the parents and ancestors the client sent, so the walk can't start |
| `no_baseline` | No full run on the platform in the history window, or the project has no coverage to walk from |

The runs request resolves the same baseline again (`baseline_sha:` fixed) to confirm it and read its full runs, and records the baseline's runs on the impact run (`baseline_run_ids`), so every shard read later derives its skip list from the tests the decision saw.

- **A window over the cap starts a new baseline.** `no_baseline` and `baseline_too_old` run every test in scope, and the commit becomes the next baseline. A long branch with a run on every commit runs everything about once every 20 measured commits.
- **A large diff runs everything.** Above 5,000 changed files the run records `diff_too_large`, runs every test in scope, and its commit becomes a baseline.
- **Every run refreshes evidence.** Every run uploads test-scoped evidence for the tests it executed, so any later checkout that reproduces it can use it. Skipped tests write nothing. Evidence expires with coverage retention (`TUIST_COVERAGE_FILE_RETENTION_DAYS`, 90 days by default), and a test whose versions all expired runs as `no_evidence`. There's no required nightly run: the default branch's runs are the baselines.

## Impact analysis rules

Selection is a pipeline of rules (`Tuist.TestImpactAnalysis.Rule`) run in a fixed order by `Tuist.TestImpactAnalysis.run/1` over one shared, read-only input. New behaviour is a new rule, not a new branch in one large function.

- **Input** (`Tuist.TestImpactAnalysis.Input`, built once per request by `load/2`): the tests in scope (the baseline runs' tests in the requested modules, `baseline_tests/3`), the changed files, the tracked-file globs, each test's evidence (`Tuist.Tests.Coverage.TestEvidence.lookup/4`, the lookup coverage carry uses, over the checkout's blobs: the baseline's listing, `GitHistory.blobs_at/3`, overlaid with the blobs of the changed files, `checkout_blobs/2`), per-module target-level evidence (with the paths the module's test and suite scopes recorded taken out), the baseline's test files, every path the baseline's evidence includes, and the flaky tests. Its independent reads run concurrently. `new/1` indexes it so rules asking the same question share one answer.
- **State** (`Tuist.TestImpactAnalysis.State`): every test starts undecided. A rule can select or skip an undecided test with its own name as the reason. A decided test is final, so the first rule that decides a test is its reason and no later rule can undo a selection.
- **Verdict**: `:continue` runs the next rule; `:done` stops and keeps the decisions; `{:abort, reason, matched_path}` discards every decision and makes the outcome `fallback`.
- **End of pipeline**: tests still undecided are selected with reason `undecided`. A test is only skipped when a rule explicitly skips it, so a missing rule or an early `:done` can only select more.
- **Rules are pure.** They do no writes and no reads of their own, so each is tested alone with a hand-built input, and the same input always gives the same decisions.
- **The order is code, versioned.** The rule list lives on the server, not in a project's configuration. Each impact run stores `rules_version` (bump `@rules_version` when a rule's behaviour or the order changes) and a `rule_trace`: per rule that ran, how many tests it selected and skipped and its verdict.

The baseline isn't a rule: it's resolved before the pipeline, and a run without one records a fallback and skips the pipeline. `diff_too_large` isn't a rule either: `Tuist.TestImpactAnalysis.Runs` checks the count before the input is loaded.

| # | Rule (`Rules.*`) | Decides | Verdict |
| --- | --- | --- | --- |
| 1 | `tracked_files` (`TrackedFiles`) | Nothing. Checks the changed paths against the project's tracked files (`GitHistory.settings(project).tracked_file_globs`), whose change can affect any test without showing in coverage. | Abort with `tracked_file_changed` and the first matching path; otherwise continue |
| 2 | `test_file_changed` (`TestFileChanged`) | Selects every test of each suite a changed test file belongs to, whether or not that test's own evidence includes it. A test file is one the baseline recorded as test code; its suites are those whose tests' newest versions include it (which holds what the suite's setup ran). A test outside any suite selects only itself. `matched_path` is the file, the first in path order when several match. | Continue |
| 3 | `failed_last_run` (`FailedLastRun`) | Selects tests whose newest reproduced version failed, or comes from a run where they were flaky. A test the checkout reproduces no version of is left to `impacted`. | Continue |
| 4 | `no_evidence` (`NoEvidence`) | Selects tests without any test-scoped version: a new test or module, a test the build system records no test-scoped evidence for, another platform, or expired evidence. | Continue |
| 5 | `impacted` (`Impacted`) | Selects tests the checkout reproduces none of their versions for: a file the test or its suite's setup executed has a different blob now. A module whose target-level evidence (what its test processes ran outside any test, such as an app's launch) includes a changed path selects all its tests. `matched_path` is the first changed path the newest version or the target evidence includes. | Continue |
| 6 | `owned_without_evidence` (`OwnedWithoutEvidence`) | Selects every test in the `affected_modules` of each changed file no evidence includes (the baseline's, a test's newest or reproduced version, or target-level): a resource, a new file, or a declarations-only file. A file no module owns (empty list) or the client couldn't classify (absent) selects nothing. | Continue |
| 7 | `unaffected` (`Unaffected`) | Skips every test still undecided. | Done |

**Tracked files are the coverage carry list.** Rule 1 reads the setting coverage carry already stops at, so a test selection skips gets carried coverage, and a commit where carry stops makes selection fall back. A narrower list would skip tests whose coverage then shows as unknown; a wider one would fall back for no reason. The list is the same for every build system today, and its defaults are Xcode's (see [Rule inputs on Xcode](#rule-inputs-on-xcode)).

**`affected_modules` come from the client's graph.** For each changed file the client lists the test modules that depend, directly or not, on the module that owns it. An empty list means no module owns the file (a README, CI configuration); absent (`nil`) means the graph can't attribute it to one module, and such files belong on the tracked list instead.

## Client ↔ server flow

Only for the coverage strategy. Default selective testing keeps its own flow and creates no impact run.

The decision is made once per invocation, before the build: in the plan job for sharded runs and in the single job otherwise. Shards make no impact-analysis calls and need no Git history.

1. **Prune.** The client runs its default selective testing. Every test module in scope is either left to decide or skipped because its hash matched.
2. **Baseline.** `POST …/tests/selective-testing/coverage/baseline` with the checked-out commit, the platform and the build context. When the checkout is a pull request's synthetic merge commit, the client also sends its two parents (`parent_shas`: the base-branch tip and the pull request head), which the server's history has. It's a merge checkout when the ref is a `refs/pull/` ref, `GITHUB_SHA` (where set) is the checked-out commit, and that commit has two parents. The parents are read from the commit object, since a depth-1 checkout grafts them away. The response is `baseline_sha` and whether the diff for that commit and baseline is already stored (`diff_cached`), or `null` with a reason. When the history doesn't reach the checkout (`history_unknown`), the client deepens once by 100 commits and repeats the request with `ancestor_shas`: the checkout's ancestors it now has, nearest first, at most 200. If the answer is still `history_unknown`, it goes on with that reason.
3. **Diff**, only with a baseline and only when it isn't cached or the checkout is dirty. The client deepens a shallow clone until the baseline is reachable, diffs the baseline against the checked-out commit, not the pull request head, reading only trees, and adds dirty and untracked files. Each changed file gets its `affected_modules`. A baseline the client can't reach is `history_unavailable`: a full clone without it, a shallow clone with no ref to deepen or no `.history` remote access, or deepening that ran out of budget or window.
4. **Runs.** `POST …/tests/selective-testing/coverage/runs`, synchronous, with a 2 s timeout: the build context, every test module in scope with whether hashing skipped it (`modules: [{name, skipped}]`), the same `parent_shas` and `ancestor_shas` as step 2, and either the baseline (plus the diff when step 2 asked for it) or the reason there's none. The server records an impact run and returns its `id`, the `outcome` (`selected` or `fallback`), the `reason` and `matched_path` of a fallback, the counts, and on `selected` the skip list. A timeout or an error means a fallback on the client, with a warning and no impact run. When every module is skipped, the server skips the diff and the rules and records a `selected` run that selects nothing, so no fallback reason can make the client run tests hashing skipped.
5. **Act on the outcome** (see [The outcome on the client](#the-outcome-on-the-client)).
6. **Plan shards** (sharded runs only), after the build as today: `POST …/tests/shards` with `test_impact_run_id` when the outcome was `selected`. The server plans the suites that have selected tests, at suite granularity. Without the ID it plans as today.
7. **Read a shard** (sharded runs only), by reference and index as today. For a plan that points to an impact run, the response also carries `skipped_tests`, the shard's skip list.
8. **Run** with the skip list applied (see [Applying the selection](#applying-the-selection)).
9. **Upload** as today, plus `test_impact_run_id` on `POST …/tests`, on fallbacks too, sharded or not. It's stored on the test run, which is how the run page finds its impact run.

### Baselines come from runs without selection

Selection doesn't treat any branch specially: the default branch selects like any other. Users run `tuist test --no-selective-testing` on the default branch, and on any other branch that shouldn't select, so each of its commits with a run is a full run with fresh evidence, and a pull request's window usually ends at its merge base. Excluded branches the user configures are a later step (see [Known limits](#known-limits)).

### The outcome on the client

| Outcome | What runs | Why |
| --- | --- | --- |
| `selected` | What hashing left, minus the skip list | Modules with nothing selected aren't built at all where the build system can avoid it |
| `no_baseline`, `baseline_too_old`, `diff_too_large` | Every test in scope, including what hashing would skip | The commit becomes the next baseline |
| Any other fallback, `not_enabled`, a failed or timed-out request | What hashing left | Exactly a default run |

What a user excluded explicitly stays excluded in the second row. The client sends the impact run's ID with every test upload of the invocation, and with the shard plan only on `selected`.

## Runs API

Both endpoints are in `TuistWeb.API.SelectiveTestingCoverageController`, under `/api/projects/{account}/{project}/tests/selective-testing/coverage`.

| Operation | Request | Response |
| --- | --- | --- |
| `POST …/baseline` (`resolveTestImpactBaseline`) | `build_system`, `commit_sha` (required); `parent_shas`, `ancestor_shas` (at most 200, the rest ignored), `platform`, the build system's block (`xcode`) | `TestImpactBaseline`: `baseline_sha` (nullable), `reason` (`history_unknown` asks the client to deepen and repeat the request with `ancestor_shas`), `diff_cached` |
| `POST …/runs` (`createTestImpactRun`) | `build_system`, `head_sha`, `modules [{name, skipped?}]` (required); `commit_sha` (defaults to `head_sha`, keys the diff), `parent_shas`, `ancestor_shas`, `baseline_sha` or `fallback_reason`, `changed_files [{path, status, blob?, affected_modules?}]` with `changed_files_count`, `dirty`, `platform`, `git_branch`, the build system's block | `TestImpactRun`: `id`, `outcome`; `reason` and `matched_path` on a fallback; `counts {requested, selected, skipped}` and `skipped_tests [SkippedTest]` on `selected` |
| `POST …/tests/shards` (`createShardPlan`) | gains optional `test_impact_run_id` | unchanged |
| `GET …/tests/shards/{reference}/{index}` (`getShard`) | unchanged | gains `skipped_tests [SkippedTest]` for a plan that points to an impact run |
| `POST …/tests` (`createTest`) | gains optional `test_impact_run_id` | unchanged |

`SkippedTest` is `{module, suite?, name?}`, named the same way for every build system. Both responses call the list `skipped_tests`, since a shard read doesn't depend on which selection produced it; the shard read's existing `skip` (the catch-all's identifiers as strings) is unchanged. The runs response includes `skipped_tests` on every `selected` outcome; sharded clients ignore it and read their shard's list.

- **Required stays minimal.** Only what every build system has is required. A required field can't become optional without breaking generated clients.
- **One block per build system.** Xcode's build context goes in `xcode`, the only block the server reads today; Gradle, Mix and Cargo get their own blocks when they need fields. A field moves to the top level only once a second build system needs it.
- **`build_system` is recorded, not used.** It's stored on the impact run and shown on its Configuration sub-tab.
- **New fields are optional**, with a default that keeps today's behaviour. **Values that will grow are strings, not enums**: the CLI's generated client turns enums into frozen Swift enums, so an unknown value would fail decoding.

## Sharding

- **Selection and planning are separate calls.** The runs call writes the selected tests before the build; `POST …/tests/shards` plans them after it, as today. A plan points to its impact run (`shard_plans.test_impact_run_id`); the impact run holds no shard information, so fallbacks need no second planning path.
- **Plans are per suite.** A coverage plan holds only the suites with selected tests (`Runs.shard_units/2`), stored in `shard_plan_test_suites` like any suite plan, and each shard's selected tests stay in `test_impact_run_tests`. Nothing is stored twice.
- **Shards are balanced on what will run**: each suite is priced at its selected tests' `test_cases.avg_duration`, a test without one counting as the median of those with one. Skipped work can lower the shard count.
- **Each shard's skip list is narrowed to its work.** A regular shard runs only its suites and skips the unselected tests inside them. The catch-all shard keeps its role of running every suite no other shard owns, so new suites still run; its list adds the modules with nothing selected, the other shards' suites, and the unselected tests everywhere else.
- **Shards can't disagree.** The decision is fixed before planning, and a shard reads the same plan, selected rows and `baseline_run_ids`. Re-running failed shards gets the same run; re-running the whole workflow gets a new plan and impact run.
- Immutable shard plans (reporting version 1) drop coverage at ingest, so sharded runs on them never become baselines.

## Applying the selection

The server sends a skip list of `{module, suite?, name?}` entries (`Runs.skip_entries/2` unsharded, `Runs.shard_skip/4` per shard): the tests in scope that weren't selected.

- A test the server doesn't know, such as one added in the change, isn't on it and runs, which keeps the invariant.
- Tests are never collapsed into a suite, because a suite can gain tests the server hasn't seen.
- A module is one `{module}` entry only when none of its tests is selected, which rules 2 and 6 rule out for any module whose test files or owned files changed.
- `{module, suite}` entries appear only in the catch-all shard's list, for the other shards' suites.
- The skip list is never stored: it's most of the suite, and it's derived from the baseline's tests and the selected rows per request.

### Per build system

Every client receives the same list and turns it into its own filters; Xcode's are under [Applying the selection on Xcode](#applying-the-selection-on-xcode). Whatever the mechanism, a test missing from the list runs, and quarantine keeps its existing path.

## Data model

Impact runs live in ClickHouse next to `shard_plans`, written and read back the same way (`Tuist.TestImpactAnalysis.Storage`: IngestRepo with a retried read), so one plan never spans two databases. The tuples are positional, since the `ch` driver drops element names from the types it inserts with.

| Table | What it holds | Retention |
| --- | --- | --- |
| `test_impact_diffs` (`Tuist.TestImpactAnalysis.Diff`) | One row per project, checked-out commit and baseline (`ReplacingMergeTree`, so identical concurrent writes collapse): `changed_files` as `(path, status, blob, affected_modules)`, at most 5,000, and `changed_files_count`. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90) |
| `test_impact_runs` (`Tuist.TestImpactAnalysis.Run`) | One row per invocation, fallbacks included: `head_sha`, `commit_sha`, `baseline_sha`, `baseline_run_ids`, `git_branch`, `dirty`, `strategy`, `build_system`, `platform`, `build_context` (the `xcode` block's `scheme`, `test_plan` and `destination`, each capped at 1,024 characters), `outcome`, `reason`, `matched_path`, `rules_version`, `rule_trace` as `(rule, selected, skipped, verdict)`, `requested_modules` (the modules left to decide; the skip lists and the run page derive skipped tests from them), `skipped_modules` (each module the client skipped because its hash matched, with its number of tests in the baseline, 0 until the baseline is confirmed), and the counts. Once the baseline is confirmed, `requested_count` and `skipped_count` include the baseline's tests in the modules hashing skipped, so `requested = selected + skipped`; a fallback then counts the modules left as selected, since all of them run. Runs that end before the baseline is confirmed record zeros. Ordered `(project_id, inserted_at, id)` for the overview's range read, with a bloom filter on `id` for the run page. | `TUIST_COVERAGE_RUN_RETENTION_DAYS` (365) |
| `test_impact_run_tests` (`Tuist.TestImpactAnalysis.RunTest`) | One row per selected test: `test_case_id`, `module_name`, `suite_name` and `name` (copied so a shard reads its suites by prefix and the client builds identifiers without a join), `reason` and `matched_path`. Ordered `(project_id, test_impact_run_id, module_name, suite_name, name)`. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (90) |
| `coverage_runs.platform` | The platform each coverage run tested, for baseline matching. | With `coverage_runs` |
| `shard_plans.test_impact_run_id` | The impact run a coverage plan distributes. | With `shard_plans` |
| `test_runs.test_impact_run_id` | The impact run of the invocation, set at ingest like `shard_plan_id` (also on `shard_test_reports` and the summary views built over them). | With `test_runs` |

- **The link sits on the test run**, not the impact run, because the impact run is written before any test run exists. Linking it the other way would mean updating a ClickHouse row after upload, and an impact run whose build fails would never get one. `test_runs` has no TTL, so an old test run can keep an ID whose impact run expired; its tab then says so.
- **Retention.** Diffs and selected tests are built from file-level evidence and can't be explained once it expires, so they share its retention; runs keep the overview's statistics for as long as coverage run totals. All three tables are in `Tuist.Tests.Coverage`'s retention tables, so `mix tuist.coverage.retention` re-applies a changed setting.
- **Evidence isn't copied.** Test evidence comes from `coverage_test_sources` and target evidence from the baseline runs' `coverage_files` rows, both written by coverage. Selection adds no index, worker or backfill of its own, and skipped tests produce no `test_case_runs` rows.
- These are stored customer data: `server/data-export.md` documents them.

## Scope and platform

- **The invocation defines the scope.** The client sends the modules left after hashing and its build context, and selection only narrows that set. Shard plans have no scope of their own: a plan belongs to one invocation, and so does an impact run.
- **Evidence is per commit, not per scope.** A test is identified by module, suite and name. Its evidence is the union across every invocation that ran it, which can only select more. The requested scope still has to be one the baseline commit ran whole.
- **A baseline matches the request's platform.** The same test can execute different files on two platforms, so `Baselines` only picks a commit whose full runs recorded the requested platform. A test the matching baseline didn't run still falls to `no_evidence`. A request without a platform matches only runs that recorded none.
- **Platform, not OS version.** CI pipelines almost always test one platform per invocation, and projects that test several run each in its own job at the same commit, so each finds a same-platform baseline. OS versions of one platform mostly change over time, as toolchains and simulators are upgraded: matching them would leave runs without a baseline after every upgrade. Evidence doesn't record the device or OS version either.

What scope and platform mean for Xcode is under [Schemes and destinations](#schemes-and-destinations).

## Server cost

The runs request is a lookup over data the baseline already ingested, so it's synchronous.

- The lookup reads every `coverage_test_sources` version of each test in scope, plus one `coverage_files` row per module of target-level evidence. A version is one per test and set of executed blobs, whichever runs recorded it, so the cost grows with tests times the distinct code states each test ran within retention, not with runs or the window. The diff is stored per commit and baseline; verdicts are recomputed on every run.
- No request waits on a job: a commit whose coverage isn't folded yet simply isn't a baseline.
- The client sends only the changed paths and blobs, never the full tree.

## Fallbacks

Selection fails open to default selective testing, as the quarantine fetch does. Fallback reasons are plain strings, never enums, so the server can add one without breaking older clients, which treat an unknown outcome as a fallback.

| Situation | Result |
| --- | --- |
| No full run in reach, or none on the requested platform | `no_baseline`, from the baseline request: every test in scope runs |
| The history has none of the checked-out commit, its parents and its ancestors, even after the client deepened by 100 commits and sent `ancestor_shas` | `history_unknown`, from the baseline request: default selective testing |
| The nearest full run is more than 20 commits with coverage back | `baseline_too_old`, from the baseline request: every test in scope runs |
| More than 5,000 changed files | `diff_too_large`: every test in scope runs |
| The baseline has no test-scoped evidence | `no_baseline_evidence`, from the baseline request: default selective testing |
| A tracked file changed | `tracked_file_changed` with the path, from rule 1: default selective testing |
| The baseline isn't in the checkout and deepening didn't reach it within its budget or window, or couldn't run | `history_unavailable`, sent by the client: default selective testing |
| The stored diff vanished, or a dirty checkout sent no changed files | `diff_unavailable`: default selective testing |
| The project or account isn't enabled | `not_enabled`, from the baseline request: default selective testing, nothing stored |
| A request timed out or failed | Default selective testing on the client, with a warning and no impact run |
| Dirty or untracked files | Selection still runs, with a diff that isn't stored |

There's no separate accuracy measurement. Default-branch runs are the safety net: a test coverage skipped on a branch that breaks shows up as a regular failure once the change reaches the default branch.

## UI

| Where | What it shows | Data |
| --- | --- | --- |
| Sidebar | "Test Selection" under Tests, when `test_impact_analysis_enabled?/3` | |
| Test Selection page (`TuistWeb.TestSelectionsLive`, `/tests/test-selection`) | The period's selected and skipped tests, skip rate and runs, with trends. The skip rate is `skipped / requested`, where both include the tests in modules skipped by hash; a Runs tab (one row per impact run, opening its test run's Selective Testing tab) and a Baselines tab (default-branch commits that measured coverage and whether each can serve as one) | `test_impact_runs` in the range, joined to their test runs by `test_impact_run_id` |
| Test run page, Selective Testing tab (`TuistWeb.TestSelection.RunTab`) | Outcome, baseline, counts and invocation, then the Tests, Modules, Changed files, Shards (for a sharded run) and Configuration sub-tabs. A fallback shows the outcome and Configuration only. The tab shows for a run with a `test_impact_run_id`, also once the impact run expired, or when the run has default selective testing data. | The run's impact run |
| &nbsp;&nbsp;Tests | Every test coverage decided, its decision and the rule, its shard and outcome, filterable; selected tests that never reported are flagged | Selected tests from `test_impact_run_tests`; skipped ones are the baseline's tests in scope minus those, with reason `unaffected` |
| &nbsp;&nbsp;Modules | Per module, tests selected of requested, skip rate, why it runs and estimated time saved. A test run with module-level selective testing data shows the run page's existing selective testing table here instead. | The Tests rows grouped by module; the replacement reads Xcode's `xcode_targets` (`Xcode.has_selective_testing_data?/1`) |
| &nbsp;&nbsp;Changed files | Path and status, whether it's a tracked file, and how many tests it selected | `test_impact_diffs` and `matched_path` |
| &nbsp;&nbsp;Configuration | Rules version, rule trace and tracked files | `test_impact_runs` |
| Test case run page, Selective Testing tab (`TuistWeb.TestSelection.TestCaseRunTab`, `?tab=selective-testing`) | Why the test ran (rule, matched path), its shard, and the files the baseline's evidence says it executed, the changed ones first | The run's `test_impact_run_tests` row and the baseline's `coverage_files` evidence |

## Known limits

- Evidence records what ran, so it can't see compile-time dependencies (a changed macro, a constant folded at compile time). Inside modules whose hash changed, rule 6 catches files no evidence includes, but not a file that some test executed and another depends on only at compile time.
- Inputs outside the project graph and the tracked files (scripts, test data loaded from outside the project, toolchain files) are invisible to both evidence and the graph.
- The window cap (20 commits with coverage) and the tracked-file list are fixed, and no branch is excluded: users pass `--no-selective-testing` where selection shouldn't run, such as the default branch. Project-specific settings would go in the project's configuration: tracked files with coverage, since carry stops at them too, and excluded branches and the window cap on the strategy.
- **No excluded paths, so monorepos fall back on unrelated changes.** The diff spans the whole repository and the default tracked globs match anywhere in it (`**/Project.swift`, `**/Package.resolved`, `**/*.xcconfig`, …). In a monorepo such as tuist/tuist, editing a fixture's `Project.swift`, or anything under another product's folder, makes the CLI project's selection fall back with `tracked_file_changed`. Unrelated files also count toward the 5,000-file cap and inflate the stored diff. Unrelated sources are already harmless, since no test's evidence includes them.
  - **The addition:** repository-relative globs a project ignores, such as `cli/Tests/Fixtures/**`, `server/**` or `app/**`. They apply to both the tracked-file check and the diff, so carry and selection keep one rule set. They'd be configured under `coverage`, next to custom tracked files.
  - **The CLI drops excluded paths before sending the diff**, so they never count toward the cap or reach the server. The server applies the same globs to tracked files when it carries coverage.
- Only Xcode selects. Another build system would send the same requests with its own block and supply the [hooks](#what-each-build-system-supplies), once the shared code stops reading Xcode's names.

## Decided against

- **Coverage instead of module hashing, falling back to it.** Coverage then had to decide the tests it has no evidence for: always running them made modules without test-scoped evidence run more than today, and letting the server consult hashes could still run more when a flaky test pulled a hash-matched module back in. Hashing first keeps the coverage strategy a strict improvement on the default.
- **A named default strategy, a "none" strategy, or environment overrides.** Leaving the strategy out already means the default, and the existing switch for selective testing already turns selection off; a second way to say either could disagree with the first.
- **Platform-aware evidence.** Recording the exact device and OS version on each test's evidence would let another platform's baseline serve, but a same-platform baseline is nearly always there.
- **Dry-run, shadow or comparison modes.** They add flags, columns and a scoring pipeline; full runs on the default branch remain the safety net.
- **Diffing full file listings on the server.** The payload grows with the repository and large listings are truncated by `commit_file_limit`. The client diff sends only what changed.
- **Caching verdicts per commit.** Verdicts depend on evidence, which can still arrive after the first run, and on the rules version. Only the diff is per commit.
- **A per-baseline path index.** It would copy the test-scoped evidence a second time and need a worker and a backfill; `coverage_test_sources` already holds what each test version executed.
- **A `target_changed` rule.** A module's hash includes transitive sources, so it would select nearly everything with evidence. Tests without evidence already run as `no_evidence`.
- **Planning shards in the runs call.** It tied the impact run to sharding settings and needed a second planning path for fallbacks.
- **An idempotency key on impact runs.** ClickHouse can't enforce uniqueness, and shards already reach the run through the newest plan for their reference.
- **Storing the skip list, or collapsing it into suites.** It's most of the suite, and a suite can gain a test the server doesn't know, which would then be skipped.

## Xcode

What only the Xcode client and its evidence do.

### Configuration

The strategy is set in `Tuist.swift`, next to the coverage option:

```swift
let tuist = Tuist(
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage()) // omit strategy for the default
    ),
    project: .tuist()
)
```

- **The strategy is optional.** `.selectiveTesting(strategy: Strategy? = nil)` and `.testInsights(selectiveTesting: SelectiveTesting? = nil)`; `nil` means default selective testing. `Strategy` is a struct with static constructors, like `TestInsights.Coverage`, not an enum: adding a parameter to an enum case breaks every manifest that wrote `.coverage`, while a new defaulted parameter on `.coverage(…)` doesn't.
- **It requires coverage uploads.** The loader rejects `.coverage()` with `coverage: .coverage(upload: false)` (`ConfigManifestMapperError.coverageStrategyRequiresCoverageUpload`).
- **Test targets must link [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 or later**, which records test-scoped evidence and reads the skip file. The manifest can't check this: a target without it has no test-scoped evidence, so its tests always run (`no_evidence`) and it's only ever skipped whole by its hash.
- **Turning it off** is the existing `--no-selective-testing` (`TUIST_TEST_SELECTIVE_TESTING`): nothing is skipped and no impact run is created. The manifest has no "off" value.
- **Only `tuist test` selects.** `tuist xcodebuild test` doesn't, and `test-without-building` reads the selection a previous build persisted in the run metadata (`RunMetadataStorage.testImpactSkip`).

#### Names in the Xcode client

| Name | Role |
| --- | --- |
| `TestImpactSelector` | Task-local actor (`TestImpactSelector.current`, set by `TestService` for the invocation) that makes the requests and holds the outcome |
| `TestImpactGraphMapper` | Asks the selector during generation and applies the outcome to the graph (`TestImpactGraphDecision`) |
| `TestImpactAffectedModules` | Each changed file's `affected_modules` |
| `TestImpactSkipList` | Turns the skip list into pruning, `-skip-testing` and the skip file |
| `ResolveTestImpactBaselineService`, `CreateTestImpactRunService` | The TuistServer clients. Neither throws: each has a 2 s timeout and maps every failure to a fallback. |

**Output.** The CLI prints the targets hashing skipped, as today, then coverage's counts (`Coverage-based test selection: N selected, M skipped, of R tests`) and the modules with nothing selected, or the fallback reason and matched path.

### Swift Testing

Under `.coverage()`, Swift Testing tests keep today's target-based behaviour: their target is skipped when its hash matches, and otherwise they run.

- **Test-scoped evidence is XCTest and XCUITest only.** TestCoverageAttribution records no `test` or `suite` scope for Swift Testing (see [Code coverage](code-coverage.md#xcode)), so every Swift Testing test in a target left after hashing is selected by `no_evidence`. Swift Testing tests are therefore never on a skip list TestCoverageAttribution can't honour, and the server needn't know which framework a test uses.
- **The fallback is per target, not per run.** A scheme can list XCTest targets, Swift Testing targets and targets that mix both, even in one file, run in one test process. Target hashes decide first, coverage decides the XCTest tests in the targets left, and Swift Testing tests run whenever their target runs. In a mixed target the listed XCTest tests are removed, and the remaining XCTest tests and every Swift Testing test run.
- **Target-scoped evidence still covers Swift Testing**, from Xcode's raw profiles, so a Swift Testing target's code is part of rule 5's target-level check and carries with its whole target.
- **Why not per test.** A Swift Testing trait has no public way to skip a test, it would have to be added to every suite, and Swift Testing runs tests in parallel by default, which leaves overlapping tests without evidence.

### Schemes and destinations

- **The build context is the `xcode` block**: `scheme`, `test_plan` and `destination`, stored in `build_context`. The CLI sends the test targets left after hashing as the modules.
- **A baseline ran the scheme in full.** The requesting scheme must be in the baseline commit's `schemes` and not in `partial_schemes`. Any `-only-testing` or `-skip-testing` narrowing (quarantined tests aside) marks a run `partial`, as described in [Code coverage](code-coverage.md#xcode).
- **Evidence is the union across schemes.** A test run by two schemes at the baseline has the files from both.
- **The platform comes from the destination.** The CLI records an `XcodeGraph.Platform` raw value (`ios`, `macos`, …) read from the `-destination`, simulators and devices folded together, on every coverage upload and sends the same value in the baseline request. Server-processed coverage has an empty platform, so those runs never serve as a baseline for a request that names one.

### Rule inputs on Xcode

- **Test-scoped evidence.** XCTest and XCUITest tests in targets that link TestCoverageAttribution record the files each test executed. Swift Testing tests and targets without the package have none, so `no_evidence` selects them. Target-scoped evidence comes from Xcode's raw profiles, which is how code that ran outside any test, such as a UI test's app launch, reaches `impacted`.
- **Tracked files.** `GitHistory`'s default `tracked_file_globs`: `Package.resolved`, `Package.swift`, `Project.swift`, `Workspace.swift`, `Tuist.swift`, `Tuist/**`, `*.xcconfig`, `*.xctestplan`, `project.pbxproj`, `Podfile.lock`, `Cartfile.resolved` and `.xcode-version`.
- **`project.pbxproj` stays.** In a plain Xcode project with file references it changes whenever a file is added, removed or renamed, so those changes fall back. A project with synchronized folders, the layout Xcode 16 and later create, lists folders instead of files, so the same changes leave it alone and select tests like a generated project. It stays because build settings live there.
- **The diff.** `GitController.changedFiles`. When the baseline commit isn't in the checkout (`git cat-file -e` with `GIT_NO_LAZY_FETCH=1`, so a partial clone doesn't fetch it), the CLI deepens a shallow clone with `git fetch --no-tags --filter=blob:none --deepen=<n> origin <refs>`, through the refs the caller names (the pull request ref and the base branch), in steps of 50 that double, capped by `GitHistoryLimits.windowCommits` and `deepenBudgetSeconds`. It then runs `git diff --raw -z --no-renames --no-abbrev --ignore-submodules=dirty <baseline> HEAD`, adds the working tree's changes (`git diff … HEAD` and untracked files from `git ls-files --others --exclude-standard`), and hashes working-tree files with `git hash-object`, dropping any whose content is back to the baseline's. Only trees are read from the object store, never blobs. `dirty` is set when the working tree has any change or untracked file.
- **`affected_modules`.** `TestImpactAffectedModules` resolves each changed file's test targets from the generated graph, or with XcodeGraphMapper for a plain Xcode project. Resources and asset catalogs are owned like sources. Files the graph can't attribute to one target (`.xcconfig`, files inside the `.xcodeproj`) are sent without the list, and they're tracked files.
- **Hash hits.** Each test target's `selective_testing_hash` and hit are in the command event's `xcode_targets`, which the Modules sub-tab and the tab's visibility check read.

### Applying the selection on Xcode

Selection runs inside project generation. `TestsCacheGraphMapper` tags the test targets whose hash already passed as prunable, as today, and `TestImpactGraphMapper` runs right after it, before anything is pruned. It's registered in the binary cache's graph mapper factory, so it needs a CLI built with the cache. Pruning has to happen there because `xcodebuild test -skip-testing:X` still builds X.

What each outcome does to the generated graph (`TestImpactGraphDecision`):

| Outcome | Graph |
| --- | --- |
| `selected` | Modules with no selected test are pruned (`prune`), so they aren't built at all |
| `no_baseline`, `baseline_too_old`, `diff_too_large` | Every test target in scope runs, hash hits included (`runAll`) |
| Any other fallback, `not_enabled`, a failed or timed-out request | As hashing left it (`unchanged`) |

`TestImpactSelector.runAllReasons` holds the reasons in the second row. A target `--skip-ui-tests` or something else made prunable before hashing stays pruned under `runAll`. The impact run's ID goes into `RunMetadataStorage.testImpactRunId`, so every `createTest` of the invocation sends `test_impact_run_id`.

`TestImpactSkipList` turns the skip list into what xcodebuild receives:

| Entry | Unsharded | Sharded |
| --- | --- | --- |
| `{module}` | Pruned from the generated project, so it isn't built or run | `-skip-testing:Module`, appended to the shard's `skip` |
| `{module, suite}` | Never sent | The catch-all shard's list of other shards' suites; already in its `skip`, so ignored |
| `{module, suite, name}` | The skip file | The skip file |

A regular shard runs its suites with `-only-testing`, as today.

**The skip file.** Single tests are removed in the test process. The CLI writes `module/suite/name` lines (`module` the test bundle name, `suite` the XCTest class without its Swift module, `name` as the result bundle names it, `testAdd()`) to a temporary file and sets `TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_SKIP_FILE` in xcodebuild's environment (`XcodeBuildEnvironment.additionalVariables`, the way `TEST_COVERAGE_ATTRIBUTION_DIR` is passed). xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the test process without the prefix, where TestCoverageAttribution 0.3.0 or later reads `TEST_COVERAGE_ATTRIBUTION_SKIP_FILE` and removes the listed XCTest tests from `+[XCTestCase defaultTestSuite]` before they run.

- It works with `test` and `test-without-building -xctestrun`, hosted unit tests and UI tests, serial and parallel clones, and test plans with their own environment. Every test bundle in the invocation reads the same file and keeps its own entries; lines for tests that don't exist and malformed lines are ignored, and an unreadable file skips nothing. Swift Testing tests are never skipped, even if listed.
- Only targets that link the package can skip single tests, which loses nothing: per-test evidence comes from the package, so a target without it has none and can only be skipped whole.
- Quarantine is unchanged: its skipped tests still go to `-skip-testing`.

#### How a skipped test shows up

A listed test is removed, not marked skipped: it's absent from the result bundle, and a class whose tests were all removed doesn't run its class `setUp`. The run page and the test case pages list skipped tests from the impact run, so nothing is lost. Marking it skipped instead (swapping the test's invocation for one that calls `XCTSkip`) would still run its instance `setUp` and `tearDown`, and ingest would have to tell Tuist's skips apart from the project's own `XCTSkip`.

#### Why not xcodebuild's own options

- **Flags don't scale.** One `-skip-testing` per test hits `ARG_MAX` (1 MiB on macOS, arguments and environment together) at around 15,000 tests, and xcodebuild reads no argument file.
- **The `.xctestrun` doesn't cover everything and changes the command.** Its `SkipTestIdentifiers` can't skip single Swift Testing tests, and using it would split `tuist test` into build-for-testing, an edit, and test-without-building.
