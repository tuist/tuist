# Coverage-based test selection

How Tuist skips the tests a change can't affect, using the per-test coverage evidence earlier runs recorded. Users see it as selective testing's coverage strategy; the code calls it test impact analysis (`Tuist.TestImpactAnalysis` on the server, `TestImpact*` in the CLI). It builds on the evidence described in [Code coverage](code-coverage.md).

**The invariant.** Coverage evidence only ever removes tests from what default selective testing would run, never adds to it, so off the default branch a coverage run never runs more than a default run. Within that, anything Tuist can't prove unaffected runs: new tests, tests without evidence, and every test whenever selection can't be computed. When coverage can't decide, the run is a plain selective testing run.

The document has two parts. The [shared model](#strategy) (baselines, the rules, impact runs and their shards, storage, the API, the UI and the flag) holds for every build system and is written in build-system terms; a build system plugs in through the [hooks](#what-each-build-system-supplies), though some shared code still reads Xcode's names (listed under the hooks). The [Xcode](#xcode) and [Mix](#mix) parts describe what only each client and its evidence do. Xcode and Mix select; Gradle and Cargo get a part like them when their selection lands. Gradle already uploads the test-scoped evidence selection reads, from JUnit Platform tests (see [Code coverage](code-coverage.md#gradle)), reports its runs' platform as none, and has its own tracked files (`gradle:` in `@tracked_file_globs`); it still lacks module hashing, a build context block and a client for the runs endpoint.

## Strategy

Coverage is a second strategy for selective testing, chosen per project in the build system's own configuration (Xcode's is under [Configuration](#configuration)). Leaving it out keeps default selective testing.

| Strategy | What it skips | Decided by | Granularity |
| --- | --- | --- | --- |
| none (default) | Test modules whose hash already passed | The client, locally | Test module |
| coverage | What the default skips, then, in the modules left, the tests whose baseline evidence touches no changed file | The client for module hashes, then the server, before the build | Test module, then test case |

- **Coverage runs on top of the default.** The client hashes and prunes test modules as today, and coverage decides the tests in the modules left. What coverage can't decide per test (tests without test-scoped evidence) keeps today's module-level behaviour. When every module's hash matched, nothing is left to decide: the client still records an impact run, with every module marked `skipped`, so its tests count as skipped, and the server records a selection of nothing without a diff or the rules.
- **Hash decisions are reported as today.** Each build system already reports its module hashes and hits with the run, also when selective testing is off, and the run page and coverage carry read them. The runs request doesn't repeat them; it only sends the modules left.
- **Turning it off** is the switch that already turns selective testing off for a run. There's no new flag or environment variable.
- **Test-scoped evidence decides tests, not baselines.** A baseline needs none: each test's evidence comes from whichever run recorded it, and tests without any are selected by `no_evidence`. A scheme whose tests never record it (Swift Testing, targets without TestCoverageAttribution) gets a regular selection that runs every test hashing left. Which tests record it is up to each build system.

### Enabling it

The server decides whether a project selects: `Tuist.FeatureFlags.test_impact_analysis_enabled?/3` requires coverage for the project (`Tuist.Tests.Coverage.supported?/1`, its build system's) and the `:test_impact_analysis` account flag, which needs an explicit toggle on canary and production and is on everywhere else. `test_impact_analysis_account_enabled?/2` is its per-account side, which `Tuist.Ops.FeatureFlags` reports. Coverage itself is on for every account, so the flag alone gates selection. No per-run flag turns it on: the project's configuration is the opt-in.

When the project isn't enabled, the baseline request answers `not_enabled`, the client runs default selective testing without deepening, diffing or calling the runs endpoint, and nothing is stored. The runs endpoint answers 404, and the Test Selection sidebar item is hidden.

### What each build system supplies

| Hook | What it is | Xcode |
| --- | --- | --- |
| **Configuration** | Where a project opts into the strategy. | [`Tuist.swift`](#configuration) |
| **Module hashing** | Which modules default selective testing prunes before coverage is asked, and where it reports hits. | [Test target hashes, `xcode_targets`](#rule-inputs-on-xcode) |
| **Test-scoped evidence** | Which tests record the files they executed. The rest fall to `no_evidence`. | [XCTest and XCUITest with TestCoverageAttribution](#swift-testing) |
| **Platform key** | What a baseline must match, recorded on every coverage upload (`coverage_runs.platform`) and sent in the baseline request. | [The destination's platform](#schemes-and-destinations) |
| **Build context** | The generic `scope` in both selection requests, matching `scheme` on the test reports. It picks which baselines qualify. Legacy clients can still send their build-system block. | [`xcode`: scheme, test plan, destination](#schemes-and-destinations) |
| **Tracked files** | Files whose change stops coverage from narrowing the run, shared with coverage carry. A list per `build_system` in `Tuist.GitHistory` (`@tracked_file_globs`); one without its own list uses Xcode's. | [Xcode's list](#rule-inputs-on-xcode) |
| **`affected_modules`** | Which test modules a changed file can affect, from a build graph. | [The generated graph or XcodeGraphMapper](#rule-inputs-on-xcode) |
| **Applying a skip list** | How whole modules and single tests are kept from running. | [Pruning, `-skip-testing` and a skip file](#applying-the-selection-on-xcode) |

**Cargo** supplies test-scoped evidence, the platform key and its tracked files so far. `tuist cargo nextest run` records `test` and `target` evidence, since nextest runs each test in its own process. Plain `cargo test` records only `target` evidence and reports its tests as overlapped, since a binary's tests share one process. Every coverage upload records the target triple as `platform` (see [Cargo](code-coverage.md#cargo)). Cargo has no selection configuration, module hashing, build-context block or `affected_modules` yet, so Rust projects get coverage and evidence but never select.

**Mix** supplies every hook but module hashing, which it doesn't have: `mix.exs` configuration, `test` and `target` evidence from ExUnit tests that run alone, no platform, the `mix` block (scheme, OTP application), its tracked files, `affected_modules` from the project's layout, and ExUnit filters. See [Mix](#mix).

**The server-side hooks live in `Tuist.TestImpactAnalysis.BuildSystem`**: which build systems select (`selects?/1`, which the sidebar reads), each one's request block and the keys an impact run stores from it (`context/1`, `context_keys/0`), the key that scopes baselines (`scheme/1`), and how a shard plan distributes a selection (`shard_granularity/1`). Adding a build system adds an entry there.

**Scope.** Both endpoints accept `scope`, a nonempty string of at most 1,024 characters, without a build-system block. It takes precedence over the block's `scheme` (`xcode.scheme`, `mix.scheme`) and must match `scheme` on the client's test reports. The server uses it for the baseline and branch overlay and stores it under the existing `build_context.scheme` key, with the runs request's `coverage_policy`, so the run reads, baseline links and coverage carry keep the same scope. The optional legacy blocks still supply the rest of the context (Xcode's `test_plan` and `destination`, Mix's `app`). Clients omitting both scope forms retain their existing unscoped baseline lookup, so any commit whose measured set lists a scheme can be its baseline; clients needing isolated test groups must send a scope.

One hook still reads Xcode's names directly:

- **Module hashing.** The run tab's module-level hash data is Xcode's `xcode_targets` (see [UI](#ui)). A build system without hashing skips no modules, so its runs show the impact run's own module table.

### Once / Struo

Once, now named Struo, selects affected test targets from its declared graph and package ownership, produces portable test plans and reports hosted partitions to Tuist. **Graph selection remains the strict default.** Coverage exclusion is an explicit, approximate opt-in: executed source lines do not describe every compile-time dependency, resource or dynamically loaded input.

The integration reuses the shared test-report, baseline and impact-run endpoints with `build_system: "once"`. `Coverage.supported?/1` accepts Once; canary and production still require the existing account selection flag. Native collectors normalize coverage before upload; the server neither parses native profiles nor constructs runner filters. The provider contract uses:

- **Identity:** canonical target as `module`, empty `suite`, opaque native unit ID as case `name`, identically in test reports, evidence and skip decisions. Display names cannot replace opaque identities.
- **Compatibility:** the same versioned `scope` in baseline and runs requests and `scheme` in test reports, bound to collector/configuration and current test inventory, plus the same `platform`. Production-source contents must not define the scope, or an ordinary edit could never use historical evidence.
- **Observation:** the neutral `coverage` block (tool/version, repository-relative files, Git blobs, executable lines and counts, partial status) and `coverage_evidence` (paths and measured scopes). An isolated exact case can supply test evidence; an aggregate target profile supplies target evidence only and cannot authorize per-test exclusion.
- **Selection:** resolve an ancestral baseline, diff against that baseline, then request a decision for graph-selected modules. The response is a skip list, never a replacement current inventory. A module-only skip entry means every baseline test in that module was excluded, so trusting it requires a compatible complete current inventory.

The runs request may send `coverage_policy` (`"strict"`, the default, or `"instrumented"`). It is kept in `build_context.coverage_policy` for audit and no longer changes the decision: since rules version 4 a changed file that no evidence includes selects nothing unless a tracked pattern matches it ([Tracked files](#tracked-files)), so the zero-hit proof `instrumented` used to skip a single target has nothing left to decide. Actual coverage hits, failed tests and missing or stale per-test evidence still select tests.

The first client increment collects isolated Go cases and narrows only whole targets, retaining portable plans' complete-inventory validation. It must retain a target unless every current unit is explicitly excluded by compatible evidence. Unknown/new/changed test inputs, partial or failed collection, unsupported collectors, incompatible or stale inventory and provider failures all retain graph-selected work. Once's tracked files are Struo/Once manifests, Starlark graph rules, Go module/workspace manifests and locks, and mise/toolchain pins; a change stops coverage narrowing. Other adapters retain graph selection until they supply compatible observations. Full runs periodically refresh history and detect coverage-selection misses.

For an early-adopter Go project, enable `coverage_per_test = true` on its `go_test` targets and configure its Tuist infrastructure destination and credentials. From a clean repository-root checkout with an `origin` remote, publish a full observation, then plan from the complete diff against the baseline:

```sh
struo test --all --coverage-report --format json
struo query test-plan --changed-path shared/source.go --format json
struo query test-plan --changed-path shared/source.go --coverage-selection --format json > plan.json
struo test --plan plan.json --format json
```

Repeat `--changed-path` for every changed path. The command without `--coverage-selection` uses graph selection only. Discovery compiles and lists the current native tests, so fresh workers need no retained test results. Baseline publication uploads bounded Git ancestry and listings through the existing history APIs; history or checkpoint processing may initially be unavailable, in which case selection retains graph work. Schedule full observations periodically rather than treating selected runs as replacement baselines. Struo's `fixtures/test_selection/go_coverage/validate.sh` exercises this flow against a disposable Tuist project, including fresh workers and conservative fallback controls.

## Naming

Users see selective testing, the name they already know, with coverage as its second strategy. "Selective testing" and "test selection" are umbrellas, since the default already selects tests and other strategies may follow, so paths name the strategy and code names the technique.

| Layer | Name |
| --- | --- |
| UI | "Test Selection" in navigation, and the run page's existing "Selective Testing" tab |
| API | `/api/projects/{account}/{project}/tests/selective-testing/coverage/…`: `POST …/baseline` and `POST …/runs`, beside `/tests/coverage`, `/tests/shards` and `/tests/git-history`. Another strategy gets its own segment beside `coverage`. |
| Server | `Tuist.TestImpactAnalysis`, with the rules in `Tuist.TestImpactAnalysis.Candidate` and the decision in `Tuist.TestImpactAnalysis.Decision`; the controller is `TuistWeb.API.SelectiveTestingCoverageController`, next to `SelectiveTestingTargetsController`; the UI's reads are in `Tuist.Tests.Selections` |
| ClickHouse | `test_impact_diffs`, `test_impact_runs`, `test_impact_run_decisions`, the `test_impact_snapshot_*` and `test_impact_line_*` test maps, and `test_impact_run_id` on `shard_plans` and `test_runs` |

The Xcode client's names are under [Configuration](#names-in-the-xcode-client).

## Concepts

| Concept | What it is |
| --- | --- |
| **Baseline** | The nearest ancestor of the checked-out commit with a live checkpoint of the requested scope on the same platform. See [Baselines](#baselines). |
| **Checkpoint** | A commit's test map for one scope (repository, scheme, platform), written by the fold from its full runs and kept 31 days: every test, numbered densely, with its status, and per repository file the bitmap of tests that executed it. See [Snapshots](#snapshots). |
| **Overlay** | A selective run's test map against its baseline's checkpoint: only the tests whose files or status changed, the checkpoint's numbering kept. The branch's newest overlay is the decision's second candidate. |
| **Evidence** | The files a test and its suite's setup executed in the run a map holds it from, plus what its module's processes executed outside any test. The fold builds the maps from `coverage_files` evidence, which then expires after two days; selection and coverage carry read only the maps, so the two always agree. |
| **Diff** | The changed files between the baseline and the commit that is actually checked out, with each file's status, blob and affected test modules: at most 5,000 entries plus the total count. Keyed by checked-out commit and baseline, so it's computed once and reused by every invocation on that commit. A dirty checkout's run falls back without storing one; only the changed files its client marked `dirty` are kept, on the run (`test_impact_runs.dirty_files`, for the file retention). |
| **Impact run** | The decision for one test invocation: the diff, the build context, the requested modules, the outcome and reason, the rule trace and the counts. Runs with a reason are recorded too. It knows nothing about shards: a shard plan points to it. A retried invocation creates a new one. |
| **Decision** | Every test of the checkpoint in the modules left, selected or skipped with the rule that decided it and the changed file that matched, stored as bitmaps of the checkpoint's test numbers. It records intent; `test_case_runs` records the outcome. |

## Baselines

`Tuist.TestImpactAnalysis.Baselines.resolve/3` walks the commit graph (`Tuist.GitHistory.ancestors/3`) from the checked-out commit, or, when the server's history doesn't have it, from every parent and ancestor the client sent that the history has, nearest first. A known ancestor's distance from the checkout is its position in `ancestor_shas`: exact for linear history, approximate across merges. With none of them in the history the walk can't start, and the answer is `history_unknown`. The walk only starts in repositories where the project has a live checkpoint, and walks a little deeper each time (64, 256, 1,024 commits, then the history window), reading the checkpoints among the commits it reached once per step, so the common case reads a few dozen commits.

A commit is a baseline when it has a live **checkpoint** (`test_impact_snapshots`, kind `checkpoint`, not expired) of the requested scope:

- of the requested scheme (the build-system block's `scheme`, `BuildSystem.scheme/1`); a request without a scheme accepts any;
- on the requested platform (see [Scope and platform](#scope-and-platform)); a request without a platform matches only runs that recorded none.

The fold writes a checkpoint for every scope a commit's **full runs** measured, once their results are processed: runs at the commit whose `coverage_runs` row isn't `partial` (no filter narrowed them and every shard reported) and whose impact run, if they have one, skipped nothing. A run whose impact run skipped tests or modules (`skipped_count` above zero) is partial whatever its coverage says, as a Mix client reports it: Xcode clients report a run whose only skips are the single tests the skip file removed as full, and its map would lack those tests. A checkpoint holds every test those runs ran, so the run needn't have uploaded test-scoped evidence: a test without any is in the map as `no_evidence` and is selected. A commit whose runs are still being processed has no checkpoint yet, so it isn't a baseline, and no request waits for one.

A **selective run whose every skip was carried** can write a checkpoint too, but that's off for now ([Which runs write a checkpoint](code-coverage.md#which-runs-write-a-checkpoint)): such a run writes an overlay like any selective run, and one that skipped everything, executing no test, writes no map, so a baseline is a full run's checkpoint. When on, it writes one for a scope no full run at the commit measured: no identifier narrowed or skipped it, every shard of its plan reported, its impact run skipped no single test (a fallback stores no decision; read off its counts, `skipped_count` beyond the tests of `skipped_modules`, as well as its decision, so an incomplete decision doesn't hide one), and every target selective testing skipped was carried by its hash ([Code coverage](code-coverage.md#the-pipeline), step 5) from a live map of the run's platform, or holds no tests under that hash (step 2). Its checkpoint holds the tests the run executed and copies of the skipped targets' rows (status, files, lines), renumbered after them: an equal hash means the same tests executed the same files. A skipped target without tests is listed in `carried_targets` without a row, so the next commit that skips it under the same hash finds it empty there. Without it, a branch that runs selectively after a tracked-file change decides from the checkpoint before the change, and falls back, until a full run. A pull request's merge checkout (`refs/pull/N/merge`) writes none, since no later checkout walks to its merge commit. The copied rows are the checkpoint's own: it expires 31 days after its run like any checkpoint, and records when its oldest copied row was measured (`evidence_measured_at`), so a target whose hash never changes is carried from copy to copy without being executed again, as selective testing never executes it either. Tests the impact run's decision skipped aren't copied into a checkpoint, since the decision only skips a test that has test-scoped evidence and carry reads it from the map that decided it, so such a run writes an overlay (see [Which runs write a checkpoint](code-coverage.md#which-runs-write-a-checkpoint)).

Distance isn't capped by a commit count. What bounds it is the checkpoints' 31-day retention, the history window, and the diff's 5,000-file limit; since a project's default branch runs in full at least daily, the nearest checkpoint is rarely more than a day behind. A checkout whose ancestors have no live checkpoint within the history window records `no_baseline`.

| Result | When |
| --- | --- |
| The baseline: `sha`, its `checkpoint`, the full runs it holds (`run_ids`) and its `distance` in commits | The nearest ancestor with a live checkpoint of the scope |
| `history_unknown` | The history has none of the checked-out commit and the parents and ancestors the client sent, so the walk can't start |
| `no_baseline` | No live checkpoint of the scope within the history window, or the project has none to walk from |

The runs request resolves the same baseline again (`baseline_sha:` fixed) to find its checkpoint, and records the checkpoint's runs on the impact run (`baseline_run_ids`).

- **A large diff applies no coverage.** Above 5,000 changed files the run records `diff_too_large`, keeps its baseline and counts its tests, and executes every test hashing left.
- **Every run refreshes evidence.** A full run writes a checkpoint and a selective run that executed tests an overlay, so a branch's next run decides from its newest evidence. Tests skipped by the decision write nothing. Maps expire after 31 days; a commit older than its newest live checkpoint's reach runs every test as `no_baseline`.

## Impact analysis rules

`Tuist.TestImpactAnalysis.Runs.create/2` checks the diff first: a changed tracked file (`Decision.tracked_path/2`, the first in path order that matches the project's tracked files) means every test of the modules left runs, with outcome `fallback`, reason `tracked_file_changed` and that path, and nothing else is read. Otherwise `Tuist.TestImpactAnalysis.Decision.decide/4` decides every test of the baseline's checkpoint in the modules left, reading only the test maps.

Each candidate map (`Tuist.TestImpactAnalysis.Candidate`) gives each test the reason of the first rule that decides it, in this order:

| # | Reason | Decides |
| --- | --- | --- |
| 1 | `test_file_changed` | Selects every test of each suite a changed test file belongs to, whether or not that test's own evidence includes it. A test file is one the run recorded as test code; its suites are those whose tests executed it (which holds what the suite's setup ran). A test outside any suite selects only itself. |
| 2 | `failed_last_run` | Selects tests that failed or were flaky in the map's run and none of whose files changed, or that failed without evidence. A test whose files changed is left to `impacted`. |
| 3 | `no_evidence` | Selects tests without test-scoped evidence: a test the build system records none for, or a test an overlay's run skipped although its files changed (`stale`). New tests aren't in any map and aren't on the skip list, so they run. |
| 4 | `impacted` | Selects tests one of whose files (its own, its suite's setup's) changed, and every test of a module whose processes executed a changed file outside any test (such as an app's launch). |
| 5 | `unaffected` | Skips every test still undecided. |

**A changed file no evidence includes selects nothing** unless a tracked pattern matches it, which the diff check catches before any rule runs. Rules version 3 had a fifth rule, `owned_without_evidence`, that selected every test of the `affected_modules` of such a file; it is gone, and the UI keeps its label for decisions stored under version 3. See [Tracked files](#tracked-files) for the trade-off.

`matched_path` is the changed file that decided the test: for `test_file_changed` and `impacted`, the first in path order among those that select it. The query computes it inside ClickHouse with a running union over the changed paths' bitmaps, so no test is expanded into a row (54 ms and 103 MiB at 5,000 changed paths, 20 of them run by all 200,000 tests).

**Two candidates.** The primary is the baseline's checkpoint against the request's diff. The second is the branch's newest overlay (on a pull request checked out as GitHub's merge commit, the previous push's merge checkout, which is never an ancestor), against a diff composed from data the server holds: the overlay's own diff, the files changed between the two checkpoints' commits when they differ, and the run's diff. It's left out when any part is missing or truncated, or a tracked file changed. A test is decided by the candidate whose evidence of it ran last among those where its files are unchanged: skipped when it passed there, `failed_last_run` when it didn't; when there's none, it's selected with the primary's reason and matched path. The primary wins ties, and its `test_file_changed` always selects, whatever the overlay says.

**A skipped test needs a name.** A skipped test without a `test_cases` row is selected as `undecided`, since the skip list identifies tests by name. Tests the checkpoint doesn't hold aren't on the skip list either, so a missing decision can only select more.

**Stored as bitmaps.** `Decision.store/4` writes the decision to `test_impact_run_decisions`: one bitmap of the checkpoint's test numbers per decision, reason, matched path and deciding map, split into chunks of ranges, each row holding the decision's test count. `Decision.stored/2` reads it back, and a decision whose chunks don't add up to that count is read as none. Each impact run stores `rules_version` (bump `@rules_version` in `Tuist.TestImpactAnalysis` when a rule's behaviour or the order changes) and a `rule_trace`: per rule, how many tests it selected and skipped.

The baseline isn't a rule: it's resolved first, and a run without one records the reason there's none. `diff_too_large` isn't a rule either: `Runs` checks the count before reading any map.

**Tracked files are the coverage carry list.** The check reads the setting coverage carry already stops at, so a commit where carry stops makes selection fall back. A test selection skips gets carried coverage straight from its stored decision: carry reads the map that decided the test (`evidence_snapshot_id`) and doesn't evaluate it again, since the decision already compared its files and the tracked files against the checkout ([Code coverage](code-coverage.md#the-pipeline), step 6). Any other skipped test is evaluated against the same baseline selection resolves, the nearest checkpoint of its scheme, preferring its platform. A narrower list would skip tests whose coverage then shows as unknown; a wider one would fall back for no reason. The defaults are the project's build system's (`GitHistory.settings/1` picks them by `build_system`), plus the patterns the project configured at the commit, which carry reads from the commit's own impact runs ([Tracked files](#tracked-files)), so a monorepo commit that only touches another toolchain's build files doesn't make selection fall back. Carry doesn't stop at them for a target skipped by its hash, which it trusts for every build input ([Code coverage](code-coverage.md#the-pipeline), step 5), so a fallback's modules that hashing skipped still carry. Xcode's is under [Rule inputs on Xcode](#rule-inputs-on-xcode).

**`affected_modules` name a test file's modules.** For each changed file the client lists the test modules whose test code it is: the test targets that own it on Xcode, the modules a `*_test.exs` defines on Mix; empty for any other file. The server reads it only for added files (status `A`): a module that gained a file is never skipped whole (see [Applying the selection](#applying-the-selection)), so a test the file adds runs. Older clients that still send every dependent module only make the server prune less.

## Tracked files

A tracked file is one whose change can affect any test without showing in coverage: dependency pins, build settings, toolchain versions, a migration, a fixture a test reads. A change to one makes the run fall back to every test of the modules hashing left (`tracked_file_changed`). Every other changed file selects only through the tests' evidence: one no evidence includes, and no pattern matches, selects nothing.

**Patterns.** Each build system has defaults in `GitHistory`'s `@tracked_file_globs` (listed under each build system's rule inputs). The project adds its own with `tracked_files`, repository-relative globs (`*`, `**`, `?`, `[...]`, as `ExcludedPaths` translates them) the client resolves from the project's root and sends with every runs request. A pattern that starts with `!` excludes what it matches, a default or the project's own include alike, so a project can opt out of a default such as `**/project.pbxproj`. `Tuist.TestImpactAnalysis.TrackedFiles` merges both and returns the first include that matches a changed file, after the excludes, with whether it's a default. The impact run stores the patterns (`tracked_files`) and the one that matched (`matched_pattern`); the runs response returns `matched_pattern` and `matched_pattern_default`, and the branch overlay, coverage carry and the run's pages read the same matcher. The patterns are part of the project's configuration, so they belong to a commit: carry has no request, so it reads them from the impact runs of the commit's runs (the newest when there are several), and a commit without one has only the defaults. A new run at the commit folds it again, so the cached reported coverage, keyed by the fold's version, never holds stale patterns.

**Where a project declares them.**

| Build system | Configuration |
| --- | --- |
| Xcode | `Tuist.swift`: `.selectiveTesting(strategy: .coverage(trackedFiles: ["Fixtures/**", "!**/project.pbxproj"]))`, relative to the directory of `Tuist.swift` |
| Mix | `mix.exs`: `tuist: [selective_testing: [strategy: :coverage, tracked_files: ["priv/gettext/**"]]]`, relative to the project's directory. The client also sends the `lib/**` and `priv/**` of every path dependency inside the repository, which aren't compiled with counters |
| Gradle | The plugin's DSL, `tuist { selectiveTesting { trackedFiles.addAll("src/test/resources/**") } }`, relative to the root project, once Gradle selects by coverage |
| Cargo | `Cargo.toml`: `[workspace.metadata.tuist.selective_testing] tracked_files = ["tests/fixtures/**"]`, relative to the workspace root, once Cargo selects by coverage |
| Bazel | `tuist.toml`: `[selective_testing] tracked_files = ["testdata/**"]`, relative to the workspace root, once Bazel reports coverage and selects by it |

The request field is the same for every build system, so a client that starts selecting needs no server change beyond `BuildSystem.selects?/1`.

**What it borrows.** Datadog Test Impact Analysis selects nothing for a changed file no coverage includes and lets the project list tracked files, a change to which runs every test, and mark tests unskippable; Gradle Develocity Predictive Test Selection and Nx affected both take extra inputs as globs on top of what the tool infers; Bazel target determinators treat `BUILD` and `.bzl` files as inputs of everything below them. From Datadog: the rule (untracked, uncovered files select nothing) and the per-project list on top of defaults. From Nx and Develocity: `!` excludes in the same list rather than a second setting. From the target determinators: Bazel's defaults.

**The trade-off.** Selecting nothing for an uncovered file skips tests that depended on it in a way coverage can't see: a template a test renders through a compiled module, a resource loaded at runtime, a constant folded at compile time. `owned_without_evidence` caught those for a whole module at once, which on a suite where most files belong to one module (an OTP application) meant every test for a README, a `.pot` file or a new migration. The project now names those inputs, and the defaults cover the common ones per build system. Full runs on the default branch catch what a project hasn't named.

## Client ↔ server flow

Only for the coverage strategy. Default selective testing keeps its own flow and creates no impact run.

The decision is made once per invocation, before the build: in the plan job for sharded runs and in the single job otherwise. Shards make no impact-analysis calls and need no Git history.

1. **Prune.** The client runs its default selective testing. Every test module in scope is either left to decide or skipped because its hash matched.
2. **Publish the history.** The client uploads the commits the server's graph lacks and the branch heads, as the run's report does (`GitHistoryService.publish`: `POST …/tests/git-history/commits/missing`, then `POST …/tests/git-history/commits`), so a new commit is in the graph before the baseline is asked for. On CI a shallow clone is first deepened until the server has the commits' parents (`connectedGitHistory`), within the history window and `deepen_budget_seconds`. The history is the commit `gitInfo` reports, the checked-out commit, so on a pull request's merge checkout it's the synthetic merge commit, the same one the diff and `commit_sha` use. It's gated as the report's is: on CI or with coverage upload, not with `TUIST_GIT_UPLOAD_ENABLED=false`, with no remote reads under `TUIST_GIT_UNSHALLOW_ENABLED=false`, and never for a run that reports without credentials. The process keeps the collection and whether its commits are up (`GitHistoryCache`, keyed by the repository's top level, commit, project and server), so the report sends them only if this upload failed. A failure only warns, and only with coverage; selection goes on.
3. **Baseline.** `POST …/tests/selective-testing/coverage/baseline` with the checked-out commit, its parents (`parent_shas`), the platform and the build context. With step 2 done the server's graph has the checked-out commit and its parents. The parents also let the server place a commit its history doesn't have: a new commit whose history step 2 couldn't upload, or a pull request's synthetic merge commit, whose two parents are the base-branch tip and the pull request head. It's a merge checkout when the ref is a `refs/pull/` ref, `GITHUB_SHA` (where set) is the checked-out commit, and that commit has two parents. The parents are read from the commit object, since a depth-1 checkout grafts them away. The response is `baseline_sha` and whether the diff for that commit and baseline is already stored (`diff_cached`), or `null` with a reason. When the history doesn't reach the checkout (`history_unknown`), the client deepens a shallow clone once by 100 commits (`git fetch --no-tags --filter=blob:none --deepen=100 origin <refs>`, through the pull request ref and the base branch) and repeats the request with `ancestor_shas`: the checkout's ancestors it now has, nearest first, at most 200. If the answer is still `history_unknown`, it goes on with that reason. After a successful step 2 this retry is only the fallback for when the history couldn't be uploaded or the upload is off.
4. **Diff**, only with a baseline and only when it isn't cached or the checkout is dirty. When the baseline isn't in the checkout, the client deepens a shallow clone once by 100 commits, unless the retry in step 3 already did: a clone is deepened at most once per invocation. It diffs the baseline against the checked-out commit, not the pull request head, reading only trees, and adds the working tree's changes, only those to files Git tracks, as the coverage run's `git_dirty` counts them, each marked `dirty`. Each changed file gets its `affected_modules`. A baseline the client can't reach is `history_unavailable`: a full clone without it, a shallow clone with no ref to deepen or no `.history` remote access, a deepen that failed or ran out of budget, or a baseline more than 100 commits beyond the checkout.
5. **Runs.** `POST …/tests/selective-testing/coverage/runs`, synchronous, with a 30 s timeout: the build context, every test module in scope with whether hashing skipped it (`modules: [{name, skipped}]`), the same `parent_shas` and `ancestor_shas` as step 3, and either the baseline (plus the diff when step 3 asked for it) or the reason there's none. The server records an impact run and returns its `id`, the `outcome` (`selected` or `fallback`), the `reason` coverage isn't applied and its `matched_path` (on `fallback`), the counts, and on `selected` the skip list. A timeout or an error means default selective testing on the client, with a warning and no impact run. When every module is skipped, the server skips the diff and the rules and records a `selected` run that selects nothing.
6. **Act on the outcome** (see [The outcome on the client](#the-outcome-on-the-client)).
7. **Plan shards** (sharded runs only), after the build as today: `POST …/tests/shards` with `test_impact_run_id` when the outcome was `selected`. The server plans the suites that have selected tests, at suite granularity. Without the ID it plans as today.
8. **Read a shard** (sharded runs only), by reference and index as today. For a plan that points to an impact run, the response also carries `skipped_tests`, the shard's skip list.
9. **Run** with the skip list applied (see [Applying the selection](#applying-the-selection)).
10. **Upload** as today, plus `test_impact_run_id` on `POST …/tests`, for runs with a reason too, sharded or not. It's stored on the test run, which is how the run page finds its impact run. The history step 2 uploaded isn't sent again; the commit's file listing still goes up once the run exists.

### The checked-out commit's files

A clean checkout's whole diff (not capped at 5,000) against a baseline whose file changes are written (`git_file_changes`, not only a listing in `git_commit_files`) is also the checked-out commit's tree: the baseline's files with the diff applied. The runs request writes it as the commit's file changes (`GitHistory.FileChanges.write_from_diff/5`), with its listing row, so when the client asks `listings/missing` before uploading the commit's listing, the commit isn't missing and the client uploads nothing. The diff carries no mode, so a path keeps the baseline's and an added path is a regular file. The commit has to be in the graph to have a place: a new commit's history is usually uploaded after the run, so the runs request finds it only when an earlier invocation uploaded it, and `listings/missing` tries again from the stored diff (`Runs.write_file_changes/3`), after the client published the commit's history and before it uploads the listing. A commit no ref owns gets a detached ref; one whose first parents reach no owned commit is left to the upload.

Nothing is written, and the client uploads the listing as before, when the checkout is dirty, the diff was capped, the baseline's file changes aren't current or its listing is truncated, the diff doesn't apply to the baseline's files (it adds a path the baseline has, or changes or deletes one it lacks), the result exceeds `commit_file_limit`, the commit has a listing already, or another write holds the repository's ref lock (the write doesn't wait for it). A write that fails never fails its request. The listing row records the files as never uploaded (`git_commit_listings.staged` false): the commit's files are known only while its file changes are current, so it counts as missing once they aren't, and an upload then replaces the row.

### Baselines come from runs without selection

Selection doesn't treat any branch specially: the default branch selects like any other. Users run `tuist test --no-selective-testing` on the default branch, and on any other branch that shouldn't select, so each of its commits with a run is a full run with fresh evidence, and a pull request's baseline is usually its merge base. Excluded branches the user configures are a later step (see [Known limits](#known-limits)).

### The outcome on the client

| Outcome | What runs | Why |
| --- | --- | --- |
| `selected` | What hashing left, minus the skip list | Modules with nothing selected aren't built at all where the build system can avoid it |
| A reason (outcome `fallback`), `not_enabled`, a failed or timed-out request | What hashing left | Coverage evidence isn't applied |

There's one path whatever the outcome: the client gets the baseline if there is one, prunes by hash, records the impact run (with the baseline when it has one, and the reason coverage evidence isn't applied when there is one) and runs what hashing left minus what the run skips. A run with a reason skips nothing, so every test of the modules hashing left runs and a coverage run never runs more than a default one. The client sends the impact run's ID, whatever its outcome, with every test upload of the invocation and with the shard plan. A fallback stores no decision, so an Xcode plan for one is built as without a run, and its shards restore the run from the test products' run metadata. A Mix plan keeps it, since Mix shards learn the run only from the plan.

## Runs API

Both endpoints are in `TuistWeb.API.SelectiveTestingCoverageController`, under `/api/projects/{account}/{project}/tests/selective-testing/coverage`.

| Operation | Request | Response |
| --- | --- | --- |
| `POST …/baseline` (`resolveTestImpactBaseline`) | `build_system`, `commit_sha` (required); `parent_shas` (the checked-out commit's parents; on a merge checkout, the base-branch tip and the pull request head), `ancestor_shas` (at most 200, the rest ignored), `platform`, the build system's block (`xcode` or `mix`) | `TestImpactBaseline`: `baseline_sha` (nullable), `reason` (`history_unknown` asks the client to deepen and repeat the request with `ancestor_shas`), `diff_cached` |
| `POST …/runs` (`createTestImpactRun`) | `build_system`, `head_sha`, `modules [{name, skipped?}]` (required); `commit_sha` (defaults to `head_sha`, keys the diff), `parent_shas` and `ancestor_shas` (as in the baseline request), `baseline_sha` or `fallback_reason`, `changed_files [{path, status, blob?, affected_modules?, dirty?}]` (`dirty`: the working tree has the file differing from the checked-out commit; absent when only commits changed it, or from a client that doesn't report it) with `changed_files_count`, `dirty`, `platform`, `git_branch`, the build system's block | `TestImpactRun`: `id`, `outcome`; `reason` and `matched_path` on a fallback; `counts {requested, selected, skipped}` and `skipped_tests [SkippedTest]` on `selected` |
| `POST …/tests/shards` (`createShardPlan`) | gains optional `test_impact_run_id` | unchanged |
| `GET …/tests/shards/{reference}/{index}` (`getShard`) | unchanged | gains `skipped_tests [SkippedTest]` for a plan that points to an impact run, and `test_impact_run_id` for one that distributes it by module (Mix) |
| `POST …/tests` (`createTest`) | gains optional `test_impact_run_id` | unchanged |

`SkippedTest` is `{module, suite?, name?}`, named the same way for every build system. Both responses call the list `skipped_tests`, since a shard read doesn't depend on which selection produced it; the shard read's existing `skip` (the catch-all's identifiers as strings) is unchanged. The runs response includes `skipped_tests` on every `selected` outcome; sharded clients ignore it and read their shard's list.

- **Required stays minimal.** Only what every build system has is required. A required field can't become optional without breaking generated clients.
- **One block per build system.** Xcode's build context goes in `xcode` and Mix's in `mix`; the server reads only the block of the request's `build_system`. Gradle and Cargo get their own blocks when they need fields. A field moves to the top level only once a second build system needs it.
- **`build_system` is recorded, not used.** It's stored on the impact run and shown on its Configuration sub-tab.
- **New fields are optional**, with a default that keeps today's behaviour. **Values that will grow are strings, not enums**: the CLI's generated client turns enums into frozen Swift enums, so an unknown value would fail decoding.

## Sharding

- **Selection and planning are separate calls.** The runs call writes the selected tests before the build; `POST …/tests/shards` plans them after it, as today. A plan points to its impact run (`shard_plans.test_impact_run_id`); the impact run holds no shard information, so runs with a reason need no second planning path.
- **Plans are per suite.** A coverage plan holds only the suites with selected tests (`Runs.shard_units/2`, from the stored decision), stored in `shard_plan_test_suites` like any suite plan, and each shard's selected tests stay in the decision's bitmaps. Nothing is stored twice.
- **Shards are balanced on what will run**: each suite is priced at its selected tests' `test_cases.avg_duration`, a test without one counting as the median of those with one. Skipped work can lower the shard count.
- **Each shard's skip list is narrowed to its work.** A regular shard runs only its suites and skips the unselected tests inside them. The catch-all shard keeps its role of running every suite no other shard owns, so new suites still run; its list adds the modules with nothing selected, the other shards' suites, and the unselected tests everywhere else.
- **Shards can't disagree.** The decision is fixed before planning, and a shard reads the same plan and stored decision. Re-running failed shards gets the same run; re-running the whole workflow gets a new plan and impact run.
- **Mix plans per module.** A Mix shard runs test files, which can't be narrowed to suites, so `BuildSystem.shard_granularity/1` is `module` for Mix: `Runs.shard_units/2` returns no suites, the plan job sends only the test modules with something selected, and the plan balances them as without a selection, keeping `test_impact_run_id`. Each shard read carries the run's whole skip list (`Runs.skipped_tests/2`) and the run, and the shard keeps the entries of its own files. A selection of nothing still plans every module, so each shard reports the run. A fallback plans every module and keeps the run too, so its shards report it without a skip list and their test runs show the reason on the Selective Testing tab and the Test Selection page, which lists only the impact runs a test run points to.
- Immutable shard plans (reporting version 1) drop coverage at ingest, so sharded runs on them never become baselines.

## Applying the selection

The server sends a skip list of `{module, suite?, name?}` entries (`Runs.skip_entries/2` unsharded, `Runs.shard_skip/4` per shard): the tests in scope that weren't selected.

- A test the server doesn't know, such as one added in the change, isn't on it and runs, which keeps the invariant.
- Tests are never collapsed into a suite, because a suite can gain tests the server hasn't seen.
- A module is one `{module}` entry only when none of its tests is selected and it gained no file. `test_file_changed` selects the suites of a changed test file; for a module that gained one (a changed file with status `A` naming it in `affected_modules`), `Decision.decide/4` keeps the file as its skipped tests' `matched_path` (never shown: the Tests tab reads it only for selected tests), and `skip_entries/2` and the catch-all shard list them test by test, so a suite or test the new file adds runs.
- `{module, suite}` entries appear only in the catch-all shard's list, for the other shards' suites.
- The skip list is never stored as names: it's derived per request from the decision's skipped bitmaps and the checkpoint's test names.

### Per build system

Every client receives the same list and turns it into its own filters; Xcode's are under [Applying the selection on Xcode](#applying-the-selection-on-xcode). Whatever the mechanism, a test missing from the list runs, and quarantine keeps its existing path.

## Data model

Impact runs live in ClickHouse next to `shard_plans`, written and read back the same way (`Tuist.TestImpactAnalysis.Storage`: IngestRepo with a retried read), so one plan never spans two databases. The tuples are positional, since the `ch` driver drops element names from the types it inserts with.

| Table | What it holds | Retention |
| --- | --- | --- |
| `test_impact_diffs` (`Tuist.TestImpactAnalysis.Diff`) | One row per project, checked-out commit and baseline (`ReplacingMergeTree`, so identical concurrent writes collapse): `changed_files` as `(path, status, blob, affected_modules)`, at most 5,000, and `changed_files_count`. | `TUIST_COVERAGE_FILE_RETENTION_DAYS` (31) |
| `test_impact_runs` (`Tuist.TestImpactAnalysis.Run`) | One row per invocation, runs with a reason included: `head_sha`, `commit_sha`, `baseline_sha`, `baseline_run_ids`, `git_branch`, `dirty`, `strategy`, `build_system`, `platform`, `build_context` (the build system's block: Xcode's `scheme`, `test_plan` and `destination`, Mix's `scheme` and `app`, each capped at 1,024 characters), `outcome`, `reason`, `matched_path`, `rules_version`, `rule_trace` as `(rule, selected, skipped, verdict)`, `requested_modules` (the modules left to decide; the skip lists and the run page derive skipped tests from them), `skipped_modules` (each module the client skipped because its hash matched, with its number of tests in the baseline, 0 until the baseline is confirmed), and the counts. Once the baseline is confirmed, `requested_count` and `skipped_count` include the baseline's tests in the modules hashing skipped, so `requested = selected + skipped`; a run with a reason then counts the modules left as selected, since all of them run. Runs that end before the server confirms the baseline record zeros, no `baseline_sha` (even when the client sent one), and the reason there's none, a selection of nothing included. Ordered `(project_id, inserted_at, id)` for the overview's range read, with a bloom filter on `id` for the run page. | `TUIST_COVERAGE_RUN_RETENTION_DAYS` (365) |
| `coverage_runs.platform` | The platform each coverage run tested, for baseline matching. | With `coverage_runs` |
| `shard_plans.test_impact_run_id` | The impact run a coverage plan distributes. | With `shard_plans` |
| `test_runs.test_impact_run_id` | The impact run of the invocation, set at ingest like `shard_plan_id` (also on `shard_test_reports` and the summary views built over them). | With `test_runs` |

- **The link sits on the test run**, not the impact run, because the impact run is written before any test run exists. Linking it the other way would mean updating a ClickHouse row after upload, and an impact run whose build fails would never get one. `test_runs` has no TTL, so an old test run can keep an ID whose impact run expired; its tab then says so.
- **Retention.** Diffs share the coverage file retention; runs keep the overview's statistics for as long as coverage run totals. Both tables are in `Tuist.Tests.Coverage`'s retention tables, so `mix tuist.coverage.retention` re-applies a changed setting. Decisions and the test maps have a fixed 31 days (see [Snapshots](#snapshots)).
- **One copy of the evidence.** Selection and carry read the test maps below, built once per commit from the runs' `coverage_files` evidence, which then expires. Skipped tests produce no `test_case_runs` rows.
- These are stored customer data: `server/data-export.md` documents them.

### Snapshots

The test maps are the evidence selection and coverage carry read. They're written for every project with coverage, whether or not it selects.

- **Test maps instead of per-test versions.** A commit's fold writes, through `Tuist.TestImpactAnalysis.Snapshots.record/3`, a **checkpoint** for each scope (repository, scheme, platform) its full runs measured (see [Baselines](#baselines)): every test, numbered densely in module, suite and name order, and an inverted index from each repository file to the tests, suites' tests and modules' tests that executed it, as roaring bitmaps. A selective run with an impact run writes an **overlay** against its baseline's checkpoint holding only the tests whose file set or status changed. A commit's later full run writes another checkpoint, and readers take the newest; earlier ones stay until they expire, since overlays use their test numbers. Maps are built inside ClickHouse from the runs' `coverage_files` evidence, only once the run's results are processed, under an id derived from their inputs.
- **Evidence is kept two days.** A run's `test`, `suite` and `target` rows in `coverage_files` expire two days after ingestion (`Tuist.Tests.Coverage.Evidence.retention_days/0`); its `run` rows keep `TUIST_COVERAGE_FILE_RETENTION_DAYS`. The fold builds the maps seconds after the run reports, so the evidence is only its input. A refold writes a map only from runs whose evidence is still whole, and adds a checkpoint from some of a commit's runs only when the scope has no live one, so an expired run can't replace a map with a partial one.
- **The decision from maps.** `Decision` decides each impact run from them (see [Impact analysis rules](#impact-analysis-rules)) and stores it in `test_impact_run_decisions`. Rows grow with the distinct reasons and matched paths, not with tests: a run that skips 190,000 of 200,000 tests stores the skipped ones as one range-compressed bitmap.
- **Coverage carry from maps.** `Tuist.Tests.Coverage.Reported.compute/3` carries skipped tests from the maps (`Tuist.TestImpactAnalysis.Carry`): the stored decision names the skipped tests, and each test map points to its tests' line sets (`test_impact_snapshot_lines`). A line set is stored once per project and week, identified by a hash of its files and lines, as the numbers of its files' line patterns: each file's distinct set of lines, also stored once per project and week, since a file's lines differ between few tests. A full run writes only the sets and patterns that changed since the week's earlier runs. A hash-skipped module carries from its source run's map, found through `coverage_target_sources`, or, once that map has expired, from the newest checkpoint that copied it under the same hash (`carried_targets`); a copy records the module's source again, so the source outlives its first 31 days while copies of it do. A copy's line sets are written into the copying run's week from the source's: a set's id is the hash of its files and lines, the same in every week.
- **Retention.** Maps and decisions expire 31 days after their run, an overlay no later than its checkpoint, and a week's line sets and patterns 31 days after the week ends. `coverage_target_sources` follows them at 31 days. A checkout with no live checkpoint among its ancestors runs every test as `no_baseline`.
- **Backfill.** The PostgreSQL migration `20261116180000_enqueue_test_impact_snapshot_backfill` queued one `Workers.SnapshotBackfillWorker` per project with coverage in the last 31 days, and `Tuist.Release.backfill_test_impact_snapshots/2` runs it again by hand; since evidence is kept two days, only runs from the last two days still write.

| Table | What it holds |
| --- | --- |
| `test_impact_snapshots` (PostgreSQL, `Tuist.TestImpactAnalysis.Snapshot`) | One row per map: kind, commit, scope, runs, its checkpoint for an overlay, and for a checkpoint that copied targets, which (`carried_targets`) and when its oldest row was measured (`evidence_measured_at`). |
| `test_impact_snapshot_tests` | A map's tests: number, `test_case_id`, module, suite, status and hashes of the files and lines it executed. |
| `test_impact_snapshot_files` | The inverted index: per file, bitmaps of the tests, suites' tests and modules' tests that executed it. |
| `test_impact_snapshot_lines` | Per map, the line set each test, suite setup and module ran, for carry. |
| `test_impact_line_sets` | Each distinct line set once per project and week, as its files' pattern numbers. |
| `test_impact_line_patterns` | Each distinct set of lines run in a file once per project and week: the file number and its line ranges. |
| `test_impact_line_paths` | The week's file numbering the patterns use. |
| `test_impact_run_decisions` | Per impact run, a bitmap of tests per decision, reason and deciding map. |

## Scope and platform

- **The invocation defines the scope.** The client sends the modules left after hashing and its build context, and selection only narrows that set. Shard plans have no scope of their own: a plan belongs to one invocation, and so does an impact run.
- **Evidence is per commit, not per scope.** A test is identified by module, suite and name. Its evidence is the union across every invocation that ran it, which can only select more. The requested scope still has to be one the baseline commit ran whole.
- **A baseline matches the request's platform.** The same test can execute different files on two platforms, so `Baselines` only picks a commit whose full runs recorded the requested platform. A test the matching baseline didn't run still falls to `no_evidence`. A request without a platform matches only runs that recorded none.
- **Platform, not OS version.** CI pipelines almost always test one platform per invocation, and projects that test several run each in its own job at the same commit, so each finds a same-platform baseline. OS versions of one platform mostly change over time, as toolchains and simulators are upgraded: matching them would leave runs without a baseline after every upgrade. Evidence doesn't record the device or OS version either.

What scope and platform mean for Xcode is under [Schemes and destinations](#schemes-and-destinations).

## Server cost

The runs request is a lookup over data the baseline already ingested, so it's synchronous.

- The decision reads the checkpoint's index rows for the changed paths only, `test_impact_snapshot_files` ordered by project, map and path, so its cost grows with the changed files, not with tests or retention: 12–19 ms for 30 changed paths and 54 ms and 103 MiB for 5,000 against a 100,000-file, 200,000-test map. The branch overlay adds the same read for its composed diff, and the checkpoint's tests (`test_impact_snapshot_tests`) are read once to name the decided ones. The diff is stored per commit and baseline; decisions are recomputed on every run.
- No request waits on a job: a commit whose coverage isn't folded yet simply isn't a baseline.
- The client sends only the changed paths and blobs, never the full tree. Writing the checked-out commit's file changes from them adds, under the repository's ref lock, a read of the diff's paths at the baseline and one `INSERT … SELECT` over the diff's paths and those the baseline and the commit's place disagree on, plus one statement per 200 written commits above the commit when it's written below others.

## Reasons coverage isn't applied

An impact run can carry a reason why coverage evidence won't narrow the modules hashing left: every test in them runs, as default selective testing would run them. A reason doesn't mean there's no baseline: the client sends one when it found none (`no_baseline`, `history_unknown`, `history_unavailable`), and the server records one for a run that has a baseline (`dirty_checkout`, `tracked_file_changed`, `diff_too_large`, `diff_unavailable`). The API and storage call such a run's outcome `fallback` and the reason `reason` (`fallback_reason` in the runs request), and the UI says "Coverage not applied".

Selection fails open to default selective testing, as the quarantine fetch does. Reasons are plain strings, never enums, so the server can add one without breaking older clients, which treat an unknown outcome as `fallback`.

| Situation | Result |
| --- | --- |
| No ancestor in the history window has a live checkpoint (31 days) of the scheme on the requested platform | `no_baseline`, from the baseline request: default selective testing |
| The history has none of the checked-out commit, its parents and its ancestors, even after the client deepened by 100 commits and sent `ancestor_shas` | `history_unknown`, from the baseline request: default selective testing |
| More than 5,000 changed files | `diff_too_large`: default selective testing |
| A tracked file changed | `tracked_file_changed` with the path, before any rule: default selective testing |
| The baseline isn't in the checkout and the single deepen of 100 commits didn't reach it, or couldn't run | `history_unavailable`, sent by the client: default selective testing |
| The stored diff vanished | `diff_unavailable`: default selective testing |
| The project or account isn't enabled | `not_enabled`, from the baseline request: default selective testing, nothing stored |
| A request timed out or failed | Default selective testing on the client, with a warning. A runs request the client gave up on may still write an impact run, which no test run points to, so the UI leaves it out |
| The client reports the checkout dirty (`dirty`), by the same check that keeps a run's coverage off its commit | `dirty_checkout`, once the baseline is confirmed and before any diff is read: default selective testing. As with coverage, the checkout's code isn't the commit's. The diff isn't stored as the commit's; the changed files the client marked `dirty` (its uncommitted changes) are kept on the run. Older clients mark none |

There's no separate accuracy measurement. Default-branch runs are the safety net: a test coverage skipped on a branch that breaks shows up as a regular failure once the change reaches the default branch.

## UI

| Where | What it shows | Data |
| --- | --- | --- |
| Sidebar | "Test Selection" under Tests, for projects whose build system selects (`BuildSystem.selects?/1`: Xcode and Mix) when `test_impact_analysis_enabled?/3` (`TestSelectionsLive.enabled?/2`). The runs list names each run by its test plan, scheme or, for Mix, OTP application | |
| Test Selection page (`TuistWeb.TestSelectionsLive`, `/tests/test-selection`) | The period's selected and skipped tests, skip rate and runs, with trends. A run's `skipped_count` includes the tests in the modules selective testing skipped by hash, so a run's skip rate is `skipped / requested` (the share of modules hashing skipped for a run without a baseline). The period's skip rate and its trend are the dashboards' test selection effectiveness over the period's impact runs: their test runs' avoided tests over their tests in scope, pooled, as `test_run_selections` recorded them (`Tuist.Tests.RunSelections`), the avoided tests of an impact run several test runs share counted once; then the period's impact runs (one row per impact run, its tests run out of requested, opening the Selective Testing tab of the latest test run that points to it). A run with a reason decides no test but still skips modules by hash: one with a baseline stored the tests in those modules as skipped and reads like any selection, and one without a baseline has no tests to count, so it reads the test modules hashing left out of all requested and the share hashing skipped, with its reason. Only impact runs some test run points to count, so a run whose client timed out stays out of the figures and the list | `test_impact_runs` in the range, joined to the range's `test_runs` (from its start to a day past its end) grouped by `test_impact_run_id`, and to their rows in `test_run_selections` |
| Test run page, Selective Testing tab (`TuistWeb.TestSelection.RunTab`) | Outcome, counts and baseline, then the Tests, Modules, Changed files and Debug sub-tabs. A sharded run's shards are on the Overview tab, and the Tests tab shows each test's shard. The rest of the invocation (scheme, destination, commit) is on the run's Overview tab. The counts are the selected tests out of requested and the skipped tests; the skip rate as on the Test Selection page; the skipped modules (the keys of `skipped_modules`) out of all requested modules; and the estimated time saved, from the baseline durations of every skipped test, in skipped modules too. The test run's overview card, Selective Testing, shows the selected tests out of requested and the skipped tests for a run with a baseline, the skip rate as on the Test Selection page, and the modules hashing skipped out of all requested modules. Whether a run shows as a selection depends only on its baseline (`Selections.has_baseline?/1`): a run with a reason and a baseline (`tracked_file_changed`, for one) shows its counts, baseline and sub-tabs, its Tests the tests that ran under its reason. A run without a baseline shows the reason, titled Coverage not applied, followed by the run page's existing selective testing table when the run has default selective testing data. The tab shows for a run with a `test_impact_run_id`, or when the run has default selective testing data, which alone shows only that table. A run without a baseline also shows only that table when it has one: coverage decided nothing to show. Once the impact run expired, the tab says so instead of hiding. | The run's impact run |
| &nbsp;&nbsp;Tests | Every requested test, its decision and the rule, and its shard, filterable by decision, reason and shard; the outcome is on the Overview tab | The stored decision's bitmaps (`test_impact_run_decisions`), expanded only for the page shown and named through the checkpoint's tests (`test_impact_snapshot_tests`); a decision that's incomplete or expired lists none. The baseline's tests in the keys of `skipped_modules` follow, with reason `module_skipped`. For a run with a reason that found its baseline, nothing is stored: the baseline's tests in `requested_modules` are selected under the run's reason. The rows name the rule, not the file that triggered it; a test case run's tab shows the file |
| &nbsp;&nbsp;Modules | Per module left to decide, tests selected of requested, skip rate within the module, why it runs and estimated time saved, then the modules hashing found not changed, each with its number of tests in the baseline. A test run with module-level selective testing data shows the run page's existing selective testing table here instead. | The Tests rows grouped by module, then `test_impact_runs.skipped_modules`; the replacement reads Xcode's `xcode_targets` (`Xcode.has_selective_testing_data?/1`) |
| &nbsp;&nbsp;Changed files | Path and status, the tracked-file pattern that matches it, and how many tests it selected, filterable by tracked; a note when the diff was capped at 5,000 files. For a dirty checkout it lists only the uncommitted changes, saying so, from `test_impact_runs.dirty_files`. Without any stored files the tab shows no count and says why: a dirty checkout whose client didn't mark its changes, or a diff past retention | `test_impact_diffs`, and the selected bitmaps' cardinality per `matched_path` |
| &nbsp;&nbsp;Config | The run's tracked-file patterns, 20 a page with the one a fallback matched first, each with its source (a Tuist default or the build system's configuration file) and the file it matched; the only tab of a fallback without a baseline | `Selections.tracked_patterns/3`: the defaults and the run's `tracked_files` |
| &nbsp;&nbsp;Debug | Tuist operators only (`Accounts.tuist_operator?/1`): the rule trace (selected, skipped and verdict per rule, aborts highlighted), then the reason coverage evidence wasn't applied and its matched path and pattern, when there is one | `test_impact_runs` |
| Test case run page, Selective Testing tab (`TuistWeb.TestSelection.TestCaseRunTab`, `?tab=selective-testing`) | Why the test ran (rule, matched path), its shard, and the files the baseline's evidence says it executed, the changed ones first | The run's stored decision for the test, and the files its baseline checkpoint's index lists it under (`Snapshots.test_files/3`) |

## Reads

The API, the MCP tools and the CLI read a run's selection through `Tuist.Tests.Selections.Query` (schemas in `Tuist.Tests.Selections.Schemas`), the same reads the run tab uses. They're read-only and not gated by the flag: a run without a coverage selection reads empty or null.

| Read | API | MCP | CLI |
| --- | --- | --- | --- |
| A run's summary: strategy, baseline, requested, selected, skipped and estimated tests | `selective_testing` on `GET /tests/:id` | `get_test_run` | `tuist test show` |
| Runs by strategy | `selective_testing` (`coverage` or `module_hash`) on `GET /tests`, also in `query`; each row's `selective_testing_strategy` | `list_test_runs` | `tuist test list --selective-testing` |
| The tests a selection decided, with decision, reason, matched path, shard and outcome | `GET /tests/:id/selective-testing/tests` | `list_selective_testing_tests` | `tuist test selective-testing list` |
| The changed files since the baseline | `GET /tests/:id/selective-testing/changed-files` | `list_selective_testing_changed_files` | `tuist test selective-testing changed-files` |
| Why a test case run's test was kept | `selective_testing` on `GET /tests/test-cases/runs/:id` | `get_test_case_run` | `tuist test case run show` |

The strategy is the run's latest `test_run_selections` row (`RunSelections.strategy_filter/3`, a Flop filter scoped to the project's rows). A fallback is recorded under `coverage`, so the `coverage` filter includes it; its tests' reason tells it apart. A run with no selective testing data has no row: it matches neither value, only `-selective_testing:"…"`. The summary has no outcome or reason, since those are each test's. Its counts are the run's `test_run_selections` row, the ones test selection effectiveness pools (`scope_tests` as requested, `avoided_tests` as skipped, their difference as selected, and `estimated_tests`), so they're each shard's own and a fallback without a baseline still counts the tests it ran. The baseline comes from the impact run. Until the row is recorded, a few seconds after the run arrives, a run with a `test_impact_run_id` reads its impact run's counts, which its shards share. The period's analytics stay page-only.

## Known limits

- Evidence records what ran, so it can't see compile-time dependencies (a changed macro, a constant folded at compile time). A changed file no evidence includes selects nothing unless it's tracked, so a project lists such inputs in `tracked_files`.
- Inputs outside the project graph and the tracked files (scripts, test data loaded from outside the project, toolchain files) are invisible to both evidence and the graph.
- The 31-day retention is fixed, and no branch is excluded: users pass `--no-selective-testing` where selection shouldn't run, such as the default branch. Excluded branches would go on the strategy, next to `tracked_files`.
- **Evidence is per baseline, not per test.** A test is decided only on the evidence in the baseline's checkpoint and the branch's newest overlay, not on any older run whose blobs the checkout happens to reproduce. A test whose files changed since the baseline runs even when an earlier commit ran the same content; the next full run on the default branch refreshes it.
- **No excluded paths, so monorepos fall back on unrelated changes.** The diff spans the whole repository and the default tracked globs match anywhere in it (`**/Project.swift`, `**/Package.resolved`, `**/*.xcconfig`, …). In a monorepo such as tuist/tuist, editing a fixture's `Project.swift`, or anything under another product's folder, makes the CLI project's selection fall back with `tracked_file_changed`. Unrelated files also count toward the 5,000-file cap and inflate the stored diff. Unrelated sources are already harmless, since no test's evidence includes them.
  - **The addition:** repository-relative globs a project ignores, such as `cli/Tests/Fixtures/**`, `server/**` or `app/**`. They apply to both the tracked-file check and the diff, so carry and selection keep one rule set. They'd be configured under `coverage`, next to custom tracked files.
  - **The CLI drops excluded paths before sending the diff**, so they never count toward the cap or reach the server. The server applies the same globs to tracked files when it carries coverage.
- Xcode and Mix select. Another build system sends the same requests with its own block, supplies the [hooks](#what-each-build-system-supplies), and adds its entry to `Tuist.TestImpactAnalysis.BuildSystem`.

## Decided against

- **Coverage instead of module hashing, falling back to it.** Coverage then had to decide the tests it has no evidence for: always running them made modules without test-scoped evidence run more than today, and letting the server consult hashes could still run more when a flaky test pulled a hash-matched module back in. Hashing first keeps the coverage strategy a strict improvement on the default.
- **A feature flag in the client.** No released CLI should depend on a flag that's later removed; the manifest option is the client's switch, and the server's `:test_impact_analysis` flag decides per project.
- **A named default strategy, a "none" strategy, or environment overrides.** Leaving the strategy out already means the default, and the existing switch for selective testing already turns selection off; a second way to say either could disagree with the first.
- **Platform-aware evidence.** Recording the exact device and OS version on each test's evidence would let another platform's baseline serve, but a same-platform baseline is nearly always there.
- **Dry-run modes for clients.** They add flags and columns to the client; the server-side test maps ([Snapshots](#snapshots)) were checked against the per-test versions they replaced by replaying runs instead.
- **Diffing full file listings on the server for the selection diff.** The payload grows with the repository and large listings are truncated by `commit_file_limit`. The client diff sends only what changed. The server does compare a stored listing with the commit below it, once per commit and outside any request, to write `git_file_changes`.
- **Caching decisions per commit.** Decisions depend on evidence, which can still arrive after the first run, and on the rules version. Only the diff is per commit.
- **Per-test versions (`coverage_test_sources`).** Each test's evidence was a version per set of executed blobs, looked up from any branch or commit that reproduced it. Evaluating every version of every test grows with tests times code states, and the table was the largest coverage stored; a map's index grows with tests times files once per commit, and is read only for the changed paths. Cross-branch reuse of a version is what was given up.
- **One table for maps and decisions without weekly line epochs.** Line sets differ between few tests, so storing them once per project and week keeps carry's lines small; a single table would copy them per run.
- **Keeping the baseline's 20-commit cap and `baseline_too_old`.** With daily full runs and 31-day maps, the nearest checkpoint is close, and an older one only selects more. Retention and the diff's 5,000-file limit bound the distance instead; the reason is gone from new runs, and old runs keep their label.
- **Checking the baseline's file listing.** The old rules compared each test's blobs with the checkout's, which needed the baseline's complete listing. The maps compare paths against the diff, which the client computes against the baseline, so neither the listing nor `commit_file_limit` limits selection.
- **A `target_changed` rule.** A module's hash includes transitive sources, so it would select nearly everything with evidence. Tests without evidence already run as `no_evidence`.
- **Planning shards in the runs call.** It tied the impact run to sharding settings and needed a second planning path for runs with a reason.
- **An idempotency key on impact runs.** ClickHouse can't enforce uniqueness, and shards already reach the run through the newest plan for their reference.
- **`owned_without_evidence`.** Selecting every test of the modules a changed uncovered file can affect turned a README, a template or a new migration into a full run on a single-module suite. A changed file without evidence selects nothing now, as on Datadog, and the project tracks what coverage can't see ([Tracked files](#tracked-files)).
- **A separate list of test modules or a manifest-based run list for new tests.** A new test isn't on the skip list, so it runs; only a module skipped whole could hide it, which the added file's status already rules out.
- **Storing the skip list, or collapsing it into suites.** It's most of the suite, and a suite can gain a test the server doesn't know, which would then be skipped.

## Xcode

What only the Xcode client and its evidence do.

### Configuration

The strategy is set in `Tuist.swift`, next to the coverage option:

```swift
let tuist = Tuist(
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage(trackedFiles: ["Fixtures/**"])) // omit strategy for the default
    ),
    project: .tuist()
)
```

- **The strategy is optional.** `.selectiveTesting(strategy: Strategy? = nil)` and `.testInsights(selectiveTesting: SelectiveTesting? = nil)`; `nil` means default selective testing. `Strategy` is a struct with static constructors, like `TestInsights.Coverage`, not an enum: adding a parameter to an enum case breaks every manifest that wrote `.coverage`, while a new defaulted parameter on `.coverage(…)` doesn't.
- **Tracked files** (`.coverage(trackedFiles:)`, empty by default) are globs relative to the directory of `Tuist.swift`. The loader makes them absolute and the selector sends them relative to the repository, dropping any outside it.
- **It requires coverage uploads.** The loader rejects `.coverage()` with `coverage: .coverage(upload: false)` (`ConfigManifestMapperError.coverageStrategyRequiresCoverageUpload`).
- **Test targets must link [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 or later**, which records test-scoped evidence and reads the skip file. The manifest can't check this: a target without it has no test-scoped evidence, so its tests always run (`no_evidence`) and it's only ever skipped whole by its hash.
- **Turning it off** is the existing `--no-selective-testing` (`TUIST_TEST_SELECTIVE_TESTING`): nothing is skipped and no impact run is created. The manifest has no "off" value.
- **Only `tuist test` selects.** `tuist xcodebuild test` doesn't, and `test-without-building` reads the selection a previous build persisted in the run metadata (`RunMetadataStorage.testImpactSkip`).

#### Names in the Xcode client

| Name | Role |
| --- | --- |
| `TestImpactSelector` | Task-local actor (`TestImpactSelector.current`, set by `TestService` for the invocation) that publishes the run's history (through `GitHistoryService`), makes the requests and holds the outcome |
| `TestImpactGraphMapper` | Asks the selector during generation and prunes the modules it returns |
| `TestImpactAffectedModules` | Each changed file's `affected_modules` |
| `TestImpactSkipList` | Turns the skip list into pruning, `-skip-testing` and the skip file |
| `ResolveTestImpactBaselineService`, `CreateTestImpactRunService` | The TuistServer clients. Neither throws: the baseline request has a 2 s timeout and the runs request 30 s, and each maps every failure to default selective testing. |

**Output.** The CLI prints the targets hashing skipped, as today, then coverage's counts (`Coverage-based test selection: N of R tests selected, M skipped by hashing or coverage`, since the counts include the tests in modules skipped by hash) and the modules with nothing selected, or `Coverage-based test selection not applied:` with the reason and matched path.

### Swift Testing

Under `.coverage()`, Swift Testing tests keep today's target-based behaviour: their target is skipped when its hash matches, and otherwise they run.

- **Test-scoped evidence is XCTest and XCUITest only.** TestCoverageAttribution records no `test` or `suite` scope for Swift Testing (see [Code coverage](code-coverage.md#xcode)), so every Swift Testing test in a target left after hashing is selected by `no_evidence`. Swift Testing tests are therefore never on a skip list TestCoverageAttribution can't honour, and the server needn't know which framework a test uses.
- **Swift Testing runs per target, not per run.** A scheme can list XCTest targets, Swift Testing targets and targets that mix both, even in one file, run in one test process. Target hashes decide first, coverage decides the XCTest tests in the targets left, and Swift Testing tests run whenever their target runs. In a mixed target the listed XCTest tests are removed, and the remaining XCTest tests and every Swift Testing test run.
- **Target-scoped evidence still covers Swift Testing**, from Xcode's raw profiles, so a Swift Testing target's code is part of `impacted`'s target-level check and carries with its whole target.
- **Why not per test.** A Swift Testing trait has no public way to skip a test, it would have to be added to every suite, and Swift Testing runs tests in parallel by default, which leaves overlapping tests without evidence.

### Schemes and destinations

- **The build context is the `xcode` block**: `scheme`, `test_plan` and `destination`, stored in `build_context`. The CLI sends the test targets left after hashing as the modules.
- **A baseline ran the scheme in full.** The requesting scheme must be in the baseline commit's `schemes` and not in `partial_schemes`. Any `-only-testing` or `-skip-testing` narrowing (quarantined tests aside) marks a run `partial`, as described in [Code coverage](code-coverage.md#xcode).
- **Evidence is the union across schemes.** A test run by two schemes at the baseline has the files from both.
- **The platform comes from the destination.** The CLI records an `XcodeGraph.Platform` raw value (`ios`, `macos`, …) read from the `-destination`, simulators and devices folded together, on every coverage upload and sends the same value in the baseline request. It's read from the destination rather than the result bundle's run destinations because the remote-processing path never parses the bundle on the client. Server-processed coverage has an empty platform, so those runs never serve as a baseline for a request that names one.

### Rule inputs on Xcode

- **Test-scoped evidence.** XCTest and XCUITest tests in targets that link TestCoverageAttribution record the files each test executed. Swift Testing tests and targets without the package have none, so `no_evidence` selects them. Target-scoped evidence comes from Xcode's raw profiles, which is how code that ran outside any test, such as a UI test's app launch, reaches `impacted`.
- **Tracked files.** Xcode's `tracked_file_globs` in `GitHistory`: `Package.resolved`, `Package.swift`, `Project.swift`, `Workspace.swift`, `Tuist.swift`, `Tuist/**`, `*.xcconfig`, `*.xctestplan`, `project.pbxproj`, `Podfile.lock`, `Cartfile.resolved` and `.xcode-version`, plus `Tuist.swift`'s `trackedFiles`.
- **`project.pbxproj` stays.** In a plain Xcode project with file references it changes whenever a file is added, removed or renamed, so those changes fall back. A project with synchronized folders, the layout Xcode 16 and later create, lists folders instead of files, so the same changes leave it alone and select tests like a generated project. It stays because build settings live there.
- **The diff.** `GitController.changedFiles`. When the baseline commit isn't in the checkout (`git cat-file -e` with `GIT_NO_LAZY_FETCH=1`, so a partial clone doesn't fetch it), the CLI deepens a shallow clone once with `git fetch --no-tags --filter=blob:none --deepen=100 origin <refs>` (`GitController.testImpactDeepenCommits`), through the refs the caller names (the pull request ref and the base branch), within `GitHistoryLimits.deepenBudgetSeconds`. A provider that only names a pull request gets a synthesized `refs/pull/<n>/merge`, which only GitHub serves, and one missing ref fails the whole fetch, so a failed deepen is retried once without it. `TUIST_GIT_UNSHALLOW_ENABLED=false` keeps selection to what the checkout has, as it does the history upload (`GitHistoryService.remoteAccess`). Deepening is preferred to fetching the baseline by SHA (`git fetch --depth=1 origin <sha>`), which is cheaper but relies on reachable-SHA wants that not every Git server allows. After the step 3 retry deepened the clone (`GitController.deepenShallowClone`), the selector passes no refs, so the diff doesn't deepen again. It then runs `git diff --raw -z --no-renames --no-abbrev --ignore-submodules=dirty <baseline> HEAD`, adds the working tree's changes (`git diff … HEAD`) as a second diff, since one diff against the working tree couldn't tell whether staged-only changes make the checkout dirty, and hashes working-tree files with `git hash-object`, dropping any whose content is back to the baseline's. Only trees are read from the object store, never blobs. `dirty` is set when the working tree changed a file Git tracks, and each file the working-tree diff lists is sent with `dirty: true`. Untracked files are left out of both, as the coverage run's `git_dirty` (`GitHistoryService.isDirtyCheckout`, `git status --porcelain --untracked-files=no`) leaves them out: on CI they're mostly what the job wrote, such as build outputs, and counting them made impact runs dirty, so their diff wasn't stored and wasn't reused, and sent them through the `tracked_file_globs` check (one under `Tuist/**` fell back). The cost is that a new source file that isn't committed selects no tests. The selector's own dirty check, which decides whether a cached diff can be reused, is `GitController.uncommittedTrackedFiles`, the same call coverage makes.
- **`affected_modules`.** `TestImpactAffectedModules` lists the test targets that own each changed file, from the generated graph or with XcodeGraphMapper for a plain Xcode project, and nothing for any other file. Paths are compared without macOS's `/private` prefix, which Git reports and XcodeGraphMapper drops; otherwise a new test file in a checkout under `/private/var` or `/private/tmp` would look unowned, and its module could be skipped whole.
- **Hash hits.** Each test target's `selective_testing_hash` and hit are in the command event's `xcode_targets`, which the Modules sub-tab and the tab's visibility check read.

### Applying the selection on Xcode

Selection runs inside project generation. `TestsCacheGraphMapper` tags the test targets whose hash already passed as prunable, as today, and `TestImpactGraphMapper` runs right after it, before anything is pruned. It's registered in the binary cache's graph mapper factory, so it needs a CLI built with the cache. Pruning has to happen there because `xcodebuild test -skip-testing:X` still builds X, and generating again after selection would double generation time.

What each outcome does to the generated graph:

| Outcome | Graph |
| --- | --- |
| `selected` | Modules with no selected test are pruned too, so they aren't built at all |
| A reason, `not_enabled`, a failed or timed-out request | As hashing left it |

`TestImpactSelector.decide` returns the modules to prune, empty for a run with a reason. The impact run's ID goes into `RunMetadataStorage.testImpactRunId`, so every `createTest` of the invocation sends `test_impact_run_id`, including the skipped-run upload of an invocation whose modules hashing all skipped.

A target some of whose tests the skip file removed doesn't store its selective-testing hash when it passes, the way a target narrowed by `-only-testing` doesn't: the tests it skipped never ran at that hash, and a later run, one with a reason included, would otherwise skip the whole target by hash.

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

### Acceptance tests

`cli/Tests/TuistCoverageSelectionAcceptanceTests` checks selection end to end against a real server. Its test copies the `CoverageTestSelection` fixture, creates a fresh organization and project, records a baseline on `main`, makes changes on branches, runs `tuist test` after each and asserts a few tests each change must or mustn't run.

- **The changes share one baseline.** Recording the baseline is the slowest step, so the source, test file, Swift Testing, merge checkout, app and sharded checkout changes run in one test against one baseline, each on its own branch from the baseline commit. The baseline runs as two shards, so it also covers the server merging shards' evidence; an unsharded baseline is the same run reported once. A decision reads only the baseline's checkpoint and its own branch's newest overlay, so one change's run can't let another skip tests it asserts ran.
- **Baselines run with `--no-selective-testing`**, as a default branch's CI does, since the default branch gets no automatic full run ([Baselines come from runs without selection](#baselines-come-from-runs-without-selection)).
- **Assertions read the CLI's output:** its selection line, which also tells a selection from a run with a reason, and xcodebuild's per-test results. The stored counts are readable since (`selective_testing` on `GET /tests/:id`), but the tests don't assert them.
- **XCTest, not Swift Testing,** so selection can later skip these tests one by one: Swift Testing records no test-scoped evidence ([Swift Testing](#swift-testing)). Not XCUITest either: the tests drive the CLI, and the fixture's own UI tests run through its nested xcodebuild.
- **The CLI runs in process and inherits only `PATH`, `DEVELOPER_DIR` and `TUIST_URL`.** The CLI hands `Environment.current.variables` to the fixture's xcodebuild, so inheriting the whole environment would pass the outer test process's coverage and TestCoverageAttribution variables (`LLVM_PROFILE_FILE`, `TEST_COVERAGE_ATTRIBUTION_DIR`, `TEST_COVERAGE_ATTRIBUTION_SKIP_FILE`) to the fixture when the suite runs with coverage.
- **The fixture's tests run serially, except in the shared baseline.** Parallel testing boots simulator clones on every run, which costs more than it saves for a fixture this size and, on a busy machine, stalls a launch for minutes or fails to launch the UI test runner. The shared baseline keeps clones, so the evidence of processes in clones Xcode deletes after the run stays covered end to end: only the baseline records the evidence the app change's UI tests are selected by. Serial output names a test's suite on the line that starts the suite rather than on every result line, and the baseline must report all of the fixture's tests, so a misread output can't pass a "didn't run" assertion.
- **Sharded runs plan at module granularity.** A fresh project has no suite timings, and suite granularity would put every suite in the one catch-all shard.
- **A target and scheme of their own, which CI only compiles until canary serves the selection endpoints.** `tuist-project-tests.yml` builds them for testing in a job of its own, which records no test results, selective testing hashes or coverage. The target then joins `TuistAcceptanceTests`, which collects coverage, so these tests record the evidence selection needs to skip them. The test runs the fixture on an iOS simulator nine times, so it stays off the production deploy path. The scheme sets `coverage: false` so `Tuist.swift`'s `coverage` option doesn't turn it on.

Run them locally before pushing any change to coverage-based test selection, on the server, the CLI or both, against a dev server running the change:

```bash
TUIST_EE=1 tuist generate --no-open TuistCoverageSelectionAcceptanceTests
TEST_RUNNER_TUIST_URL=http://127.0.0.1:8080 xcodebuild test -workspace Tuist.xcworkspace \
  -scheme TuistCoverageSelectionAcceptanceTests -destination platform=macOS
```

- **Use the dev server's own port.** A worktree's server listens on `$TUIST_SERVER_PORT`, not always 8080. The suite logs in as the seeded `tuistrocks@tuist.dev`, which `mise run db:seed` creates.
- **`xcode-select` must point at the Xcode the build uses** (`.xcode-version`). The fixture's manifests compile with `/usr/bin/xcrun swift`, and the test harness's mocked environment hands manifest loading no `DEVELOPER_DIR`, so setting it doesn't help: a `ProjectDescription` built by a newer Xcode then fails to parse ("expected '{' in struct").
- **The suite logs in once per run.** A dev server allows 10 logins per IP plus one a minute, so a second run soon after the first fails with `tooManyRequests`: start the server with `TUIST_AUTH_RATE_LIMIT_BUCKET_SIZE=1000`.

## Mix

What only the Mix client (`tuist_ex`) and its evidence do. The client is `TuistEx.Analytics.TestSelection`, called by `mix tuist.test` and `mix tuist.test.build`; the diff is `TuistEx.Git.changed_files/4`, a port of the CLI's `GitController+TestImpact.swift` that must stay in step with it.

### Configuration

```elixir
def project do
  [
    tuist: [
      project: "account/project",
      selective_testing: [strategy: :coverage, tracked_files: ["priv/gettext/**"]]
    ]
  ]
end
```

- **A run selects only with `--cover`.** Evidence comes from the run's coverage, and a run that skips tests without measuring would leave the next run no fresher evidence. A run without `--cover`, such as a local `mix test` through the `tuist.test` alias, runs every test and asks nothing.
- **Turning it off** is `--no-selective-testing`, on `mix tuist.test` and `mix tuist.test.build`: nothing is skipped and no impact run is created. The run still records evidence, so default-branch runs that pass it are baselines.
- **Not from an umbrella's root**, where each application runs a suite of its own: run inside the application, as for sharding.

### No hashing step

Mix has no module hashing: compiled modules carry no input hash a run can compare, and a test module's dependencies on the project's code are runtime calls Mix doesn't record. So coverage decides every test: the unit is the ExUnit test module, as runs report it; the runs request lists every test module of the suite (each test file parsed without loading it, `TestSelection.index/1`) with `skipped: false`; `skipped_modules` stays empty; and a run with a reason runs everything. The run's skip rate is coverage's alone.

### Evidence

A run that records evidence runs one test module at a time (`--max-cases 1`, appended by `mix tuist.test`), so every ExUnit test records `test` evidence with its lines, and every test module a `target` scope, whether or not its module is `async: true`. Sharding with `mix tuist.test.build` gives back the parallelism. A test that still overlapped something is reported as overlapped and always runs (`no_evidence`). Lines go to disk as each test ends and into the request as it's deflated, so memory doesn't grow with the suite. See [Code coverage](code-coverage.md#mix).

Evidence names more than `.ex` files. A template compiled into a module (a LiveView's `.html.heex`, `embed_templates`, `EEx.function_from_file`) has lines of its own, so a template change selects only the tests that rendered it, not every test of the suite as a file no evidence included did. A module's `@external_resource` files (a Gettext backend's `.po` files, a template, data read at compile time) are in every scope that ran any of the module's code, without lines, so changing one selects the tests that ran its module. Both are in the run's `coverage` block too, the resources with no executable lines, since a snapshot keeps only the paths a run's report holds. See [Code coverage](code-coverage.md#mix).

### Scope, platform and build context

- **The `mix` block** holds `scheme` (`mix tuist.test --scheme`, an execution variant such as a database version), which scopes baselines as Xcode's scheme does, and `app`, the OTP application, for display. Both are stored in `build_context`.
- **No platform.** Mix runs record none, so baselines match runs that recorded none.

### Rule inputs on Mix

- **Tracked files.** Mix's `tracked_file_globs` in `GitHistory`: `mix.exs`, `mix.lock`, everything under `config/`, `test_helper.exs`, Ecto's migrations (`priv/repo/migrations/**`: the schema every test's database starts from, which no evidence shows), and the toolchain pins `.tool-versions`, `mise.toml` and `.mise.toml`, at any depth; then the project's `tracked_files`, resolved from its directory, and the `lib/**` and `priv/**` of every path dependency inside the repository, umbrella siblings included (`TestSelection.tracked_files/3`).
- **`affected_modules`** (`TestSelection.owner/4`): a test file lists the modules it defines, any other file none. Each test's evidence names its own test file without lines (ExUnit doesn't compile test files with counters), so an edited test file selects its tests through `test_file_changed`, as Datadog's and selective-elixir-exunit's per-test coverage does; a new test file's module is never skipped whole, so its tests run. A file no test executed at runtime, such as a module only used at compile time, a new module or a `.pot` file, selects nothing unless it's tracked (a template or an external resource is in evidence).
- **The diff and deepening** are the CLI's ([Rule inputs on Xcode](#rule-inputs-on-xcode)), with the same 5,000-file cap, the one deepen by 100 commits through the pull request ref and the base branch, and `TUIST_GIT_UNSHALLOW_ENABLED=false`. The run's Git history goes up before the baseline request (`GitHistory.publish/2`), when the run collects it (on CI or with coverage).
- **Timeouts.** The baseline request has 5 s, since the client's HTTP stack may start with it, and the runs request 30 s; each maps every failure to running everything, with a warning. A run without a project or credentials only logs it with `TUIST_DEBUG=1`, as the quarantine read does.

### Applying the selection on Mix

`SelectionFilter` leaves the skip list out by the identity the formatter reports, `{module, describe or "", name}`, or a whole module. The skip list stays a skip list: a test the server hasn't seen, such as one the change adds, runs because nothing names it.

- **Why not `mix test` filters.** ExUnit's filters each match one tag. `--exclude test:NAME`, which quarantine uses, also matches a same-named test in another module, and `--exclude location:path:line` matches the closest test before the line in every module of the file. Neither can name a test whose name is built at compile time, such as one generated in a `for`.
- **Why not `only_test_ids`.** It's a run list: Mix starts ExUnit's runner, which reads it, before it loads the test files, so a run list has to be known before the tests are, and tests it doesn't name are dropped without being reported. `--failed` also overwrites it.
- **How.** The runner calls `ExUnit.Filters.eval/4` for every test, with its module and name among the tags. `SelectionFilter.install/0` replaces that module for the VM (`ExUnitPatch`, as `Evidence` replaces `ExUnit.OnExitHandler`): ExUnit's own code is compiled from its debug info under another name, and the replacement calls it, then answers `{:excluded, "due to tuist_unselected filter"}` for a listed test ExUnit would have run. A test ExUnit excludes or skips keeps its answer, and one an include filter picks (`--only`, `file:line`, `--include`) runs, as with any exclusion. A whole module's tests are excluded, so its `setup_all` doesn't run.
- **When it can't be installed.** The task installs it before asking the server. An ExUnit whose `ExUnit.Filters` lacks `eval/4` or debug info gets no selection: the run warns and runs every test, without an impact run. Nothing falls back to filters.
- **Excluded, not skipped.** ExUnit reports the tests as excluded, the formatter doesn't record them, and they aren't in `skip_test_identifiers`: the impact run names them. Quarantine keeps its own filters beside them. Tests the project skips in code (`@tag :skip`) or its test helper excludes aren't selection either.
- **The run's coverage is partial** when the skip list holds anything, so the fold writes an overlay rather than a checkpoint.
- **Retries** apply the same skip list: it's written to a file the retry process reads (`TUIST_EX_RETRY_SELECTION`), and the retry installs the filter too. ExUnit keeps a failure on record until the test passes, so `--failed` would otherwise rerun a test that failed in an earlier run and is skipped now.
- **Shards** apply the run's whole list from the shard read (see [Sharding](#sharding)), which only matches the tests of their files, and report `test_impact_run_id` from it.
- `test_impact_run_id` goes on every run of the invocation, a run with a reason included; an unsigned report strips it, as it strips shard references.

**Output.** `Tuist: coverage-based test selection: N of R tests selected, S skipped`, then the modules with nothing selected, or `Tuist: coverage-based test selection not applied:` with the reason and matched path.

### Tests

- `tuist_ex/test/tuist_ex/analytics/test_selection_test.exs`: the requests and the outcome against a stub server over a real repository (a selection with each changed file's `affected_modules`, a cached diff, a dirty checkout, every reason the client sends and those the server returns, `not_enabled`, failed requests, an outcome the client doesn't know), and the test index.
- `evidence_test.exs`: attribution in a VM of its own (serial tests, overlapping `async: true` modules and the same modules one at a time, a `setup_all` and its `on_exit`, what ran before any test), the JSON written from disk with and without lines, and the positional counter diff.
- `coverage_test.exs` (`attach_evidence/5`): evidence past the inline threshold, or within it but too large for the report inflated, is uploaded as deflated NDJSON and the run names the key; otherwise, or against a server without evidence uploads, it stays inline; a failed upload is reported.
- `http_test.exs`: a body holding a JSON file is deflated and reads the file into it.
- `selection_filter_test.exs`: in a VM of its own, the filter leaves out exactly the listed tests and modules (a same-named test in another describe or another module of the file, a generated name, and a new test still run; a skipped module's `setup_all` doesn't), keeps ExUnit's reason for `@tag :skip` and other filters, lets an include filter win, and a module that doesn't look as expected isn't replaced.
- `tuist.test_test.exs`: the task applies the selection beside quarantine, reports the impact run, makes coverage partial, runs everything on a fallback, a failure, without `--cover` and with `--no-selective-testing`, and hands the skip list to retries.
- `git_test.exs`: the diff against the working tree, a revert dropping out, untracked files left out of the diff and the dirty check, deepening a shallow clone once.
- Server: `evidence_test.exs` reads uploaded evidence while the run is created (rows, test case states, status) and an unreadable or missing object as `failed`; the Mix cases in `runs_test.exs` (a selection from Mix evidence with an overlapped test selected as `no_evidence`, the `mix` block as `build_context`, scheme scoping, another build system's block ignored, a module-granular shard plan), the controller and the Test Selection page.

### Known limits on Mix

- **Compile-time dependencies.** A changed macro's expansion runs in its callers' lines, so a test that exercises it executes the caller's file, not the macro's. The macro's file selects every test only when no test executed it at runtime.
- **Recording runs modules one at a time**, so a suite that relies on `async: true` takes longer unless it's sharded. A selective run that skips most tests is short either way.
- **Collection costs a read of every counted module once per test** (about 8 ms per 2,000 modules), so only projects that select collect.
- **Large evidence is uploaded** to object storage with its lines (see [Code coverage](code-coverage.md#mix)). Only a server without evidence uploads gets it inline without lines past its body limit (carried coverage then has a gap for the tests a later run skips), or not at all past it even without lines.
