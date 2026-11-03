# Coverage test selection test bed

A sample app, a script that builds a git history over it, and the expected decision for every
scenario of coverage-based test selection (the `.coverage` selective testing strategy). Every
step that implements the feature is checked against `golden.json`: the server rules (one
integration test per scenario), the CLI orchestration, and the end-to-end runs.

## Layout

| Path | What it is |
| --- | --- |
| `common/` | The app's sources, tests, resources and `Configs/Base.xcconfig`, shared by both variants. |
| `generated/` | The Tuist variant: `Project.swift`, `Tuist.swift`, `Tuist/Package.swift` and `Tuist/Package.resolved`. |
| `xcodeproj/` | The plain Xcode variant: `Shop.xcodeproj`, with its `Package.resolved`, and `Tuist.swift`. |
| `scenarios.sh` | Assembles a variant into a new repository and commits the scenarios. |
| `golden.json` | The expected outcome, selected tests and reasons per scenario. |

Both variants have the same repository layout, so paths in `golden.json` hold for either.

## The app

| Target | Kind | Covers |
| --- | --- | --- |
| `Core` | Static library | `Money.swift`, executed by almost every test; `Discount.swift`; `Models.swift`, declarations only |
| `Catalog` | Dynamic framework | `Catalog.swift`, which loads the `products.json` resource; `Search.swift` |
| `App` | iOS app | SwiftUI app with an asset catalog, depending on `Catalog` and `Core`; `Receipt.swift` runs only when the receipt is shown |
| `CoreTests` | XCTest | Three suites; `Support/Prices.swift`, a helper two of them call |
| `CatalogTests` | XCTest and Swift Testing | A suite with a class `setUp`, a test reading `CatalogTests/Fixtures/catalog-fixture.json` (outside every target), and a Swift Testing suite |
| `AppTests` | Swift Testing, hosted by `App` | |
| `CheckoutTests` | XCTest, hosted by `App` | Per-test evidence of app code |
| `AppUITests` | XCUITest | `ShopUITestCase`, a base class that launches the app in `setUp` and terminates it in `tearDown`; a test that relaunches the app; a suite whose class `setUp` launches one app for all its tests |

Every test target links [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution),
the SPM dependency. The generated variant links it statically and adds `-ObjC`; the plain project
uses Xcode's own package integration. The `Shop` scheme runs every test target in parallel with
coverage on; `ShopAppCoverage` is the same but gathers coverage for `App` and `Catalog` only. TestCoverageAttribution records per-test evidence for XCTest and UI tests only, and
XCTest runs one test at a time in each clone, so parallel testing doesn't change it. Swift Testing
tests record no test scope: what they execute is target-level evidence.

`golden.json`'s `baseline_evidence` lists the repository files each test, suite and target
executed on a measured full run, reduced the way the CLI reduces TestCoverageAttribution's output
and Xcode's per-process profiles. Both variants record the same evidence.

## Building and testing a variant

```bash
cli/Tests/Fixtures/CoverageTestSelection/scenarios.sh build generated /tmp/test-bed
cd /tmp/test-bed && tuist install && tuist generate --no-open
xcodebuild test -workspace Shop.xcworkspace -scheme Shop \
  -destination 'platform=iOS Simulator,name=iPhone 17' -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO
```

For the plain variant, build `xcodeproj` and pass `-project Shop.xcodeproj` instead. Set
`TEST_RUNNER_TEST_COVERAGE_ATTRIBUTION_DIR` to a fresh directory to see what
TestCoverageAttribution records.

## The history

`scenarios.sh build <generated|xcodeproj> <dir>` commits the variant as `baseline` on `main`, then
one branch per scenario, and prints every ref. Identity, dates and git settings are fixed, so a
fixture revision always produces the same SHAs. The script tags each scenario's checkout as
`checkout/<scenario>` and each commit a scenario records a run on as `run/…`.

- `scenarios.sh checkout <repo> <scenario>` checks a scenario out on its branch, detached for
  `local_merge`, and leaves the uncommitted edits for `dirty_checkout`.
- `scenarios.sh check <repo>` fails when `golden.json` names a ref, branch or scenario the
  history doesn't have.

## Scenarios

| Scenario | Change against the baseline | Expected |
| --- | --- | --- |
| `source_change` | `Discount.swift` | Its tests and `testApplyingDiscountUpdatesTotal` are `impacted`; `MoneyTests` and `testShowsCatalog` are skipped |
| `shared_file` | `Money.swift` | Everything left is `impacted` |
| `resource_change` | `products.json` | `owned_without_evidence` for every XCTest test depending on `Catalog` |
| `asset_catalog_change` | `Brand.colorset` | `owned_without_evidence` for the UI tests |
| `test_file_change` | `DiscountTests.swift` | Its suite is `test_file_changed` |
| `new_test` | A new test in `DiscountTests.swift` | It runs, unknown to the server |
| `failed_at_baseline` | `docs/notes.md`; the baseline ran with `testAddsAmounts` failing | Only `testAddsAmounts` runs in `CoreTests` (`failed_last_run`) |
| `carried_evidence` | A run on `Money.swift`, then `Discount.swift` | The first run's evidence keeps `MoneyTests` and `testShowsCatalog` skipped |
| `window_at_cap` | 20 measured commits since the baseline | Selected |
| `window_over_cap` | 21 measured commits | `fallback`, `baseline_too_old` |
| `window_unmeasured` | 21 commits without runs | Selected: unmeasured commits don't count |
| `default_branch` | A commit on `main` | `fallback`, `excluded_branch` |
| `diff_too_large` | 5,002 changed files | `fallback`, `diff_too_large` |
| `tracked_file` | `Configs/Base.xcconfig` | `fallback`, `tracked_file_changed` |
| `declaration_only_change` | `Models.swift` | `owned_without_evidence` for everything depending on `Core` |
| `unowned_file` | `README.md` and `Discount.swift` | Same as `source_change` |
| `unowned_file_only` | `README.md` | Every target's hash matches: `no_selection_call` |
| `unowned_test_fixture` | `catalog-fixture.json` | `no_selection_call`, so nothing runs: accepted gap |
| `dirty_checkout` | Uncommitted `Discount.swift`, untracked `Featured.swift` | Differs per variant: the plain project doesn't own the new file |
| `local_merge` | Merge commit of a branch (`Discount.swift`) into `main` (`Catalog.swift`) | Both sides' changes select tests |
| `swift_testing_only_source` | `Search.swift`, executed only by Swift Testing | Every `CatalogTests` test runs |
| `no_baseline` | `source_change`'s commit, nothing recorded | `fallback`, `no_baseline` |
| `stale_base` | `source_change`'s commit after `main` moved on with a full run | Same as `source_change`: the baseline is the merge base |
| `coverage_targets_subset` | `source_change` under `ShopAppCoverage` | Same as `source_change`: Xcode instruments every target and only narrows the report |
| `receipt_change` | `Receipt.swift`, reached through a relaunch and a shared app | The relaunching test and both tests of the shared-app suite are `impacted` |
| `test_helper_change` | `CoreTests/Support/Prices.swift` | `test_file_changed` for the suites that called it |
| `ui_test_base_class_change` | `ShopUITestCase.swift` | `test_file_changed` for its subclasses |
| `deleted_test_file` | `MoneyTests.swift` deleted | The server still decides its tests; the plain project falls back (`project.pbxproj`) |
| `renamed_source` | `Discount.swift` renamed | Its tests are `impacted`; the rest of `Core`'s dependents `owned_without_evidence`; the plain project falls back |

## `golden.json`

Each scenario has:

- `runs`: the runs to record before the checkout, in order, each with its `ref`, the `branch` to
  run it on, and any `env`, `scheme` or `edits` (the files `scenarios.sh` changes at that ref).
  The baseline is a default-branch run, so it runs every test.
- `checkout`: the `ref` and `branch` of the invocation under test (`merge_parents` for
  `local_merge`), and `baseline`, the run expected to be its baseline. `scheme` overrides the
  top-level scheme.
- `changed_files`: what the CLI sends, with `affected_modules`.
- `hash.skipped`: the test targets selective testing skips by hash before the selection call.
  `null` means no pruning. `tuist hash selective-testing` passes no destination, so it leaves out
  UI test targets, which `tuist test` does hash; `AppUITests`' entries come from `App`'s measured
  hash and its own sources.
- `outcome` and `reason`. For `selected`, `run` maps each test that runs to its `reason` and
  `matched_path`, and `skip` maps each skipped test to `unaffected`. Tests in targets skipped by
  hash aren't listed. `known_to_server: false` marks a test the baseline doesn't have, and
  `exists_at_checkout: false` one the checkout deleted. For `fallback`, `run_targets` are the targets that run whole.
  `no_selection_call` means hash pruning skipped every target, so the CLI never asks the server.
- `variants.xcodeproj`: fields that differ for the plain project.

The hash stage was measured on the generated variant. The top-level `assumptions` list the
readings of the design the decisions depend on, such as what target-level evidence includes.
When a later step settles one differently, update the decisions and the assumption together.

## How later steps use it

- **Server rules (step 4).** Seed each scenario's runs with the declared evidence, apply the
  pipeline to the checkout's `changed_files` and the targets left after `hash.skipped`, and
  compare with `run` and `skip`.
- **CLI (step 6).** Check the diff, `affected_modules` and hash pruning a checkout produces
  against `changed_files` and `hash.skipped`.
- **End to end (step 7).** For each scenario, with a fresh project and cache, record its `runs`
  with `tuist test`, then run the checkout and diff the impact run against the golden entry.
  `Tuist.swift` gains `selectiveTesting: .selectiveTesting(strategy: .coverage())` once the
  manifest API exists.

## Changing the fixture

Edits to `common/` change evidence and hashes. Re-measure `baseline_evidence` on a full run,
update the affected scenarios, re-measure the hash stage with `tuist hash selective-testing` at each checkout, and
run `scenarios.sh check` on a fresh build. Regenerate `xcodeproj/Shop.xcodeproj` when targets
change, and keep both variants' `Package.resolved` on the same TestCoverageAttribution version.
