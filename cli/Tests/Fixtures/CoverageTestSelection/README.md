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
| `App` | iOS app | SwiftUI app with an asset catalog, depending on `Catalog` and `Core` |
| `CoreTests` | XCTest | Two suites with disjoint evidence |
| `CatalogTests` | XCTest and Swift Testing | A suite with a class `setUp`, a test reading `CatalogTests/Fixtures/catalog-fixture.json` (outside every target), and a Swift Testing suite |
| `AppTests` | Swift Testing, hosted by `App` | |
| `AppUITests` | XCUITest | Two tests whose evidence differs only by `Discount.swift` |

Every test target links [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution),
the SPM dependency. The generated variant links it statically and adds `-ObjC`; the plain project
uses Xcode's own package integration. The `Shop` scheme runs every test target in parallel with
coverage on. TestCoverageAttribution records per-test evidence for XCTest and UI tests only, and
XCTest runs one test at a time in each clone, so parallel testing doesn't change it. Swift Testing
tests record no test scope: what they execute is target-level evidence.

`golden.json`'s `baseline_evidence` lists, per test, the repository files it executes. The tests
are written so that evidence follows from the code; step 7 confirms it on real runs.

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
| `unowned_file_only` | `README.md` | Every hashed target matches |
| `unowned_test_fixture` | `catalog-fixture.json` | Nothing runs: accepted gap |
| `dirty_checkout` | Uncommitted `Discount.swift`, untracked `Featured.swift` | Differs per variant: the plain project doesn't own the new file |
| `local_merge` | Merge commit of a branch (`Discount.swift`) into `main` (`Catalog.swift`) | Both sides' changes select tests |
| `swift_testing_only_source` | `Search.swift`, executed only by Swift Testing | Every `CatalogTests` test runs |
| `no_baseline` | `source_change`'s commit, nothing recorded | `fallback`, `no_baseline` |

## `golden.json`

Each scenario has:

- `runs`: the runs to record before the checkout, in order, each with its `ref`, the `branch` to
  run it on, and any `env`. The baseline is a default-branch run, so it runs every test.
- `checkout`: the `ref` and `branch` of the invocation under test (`merge_parents` for
  `local_merge`).
- `changed_files`: what the CLI sends, with `affected_modules`.
- `hash.skipped`: the test targets selective testing skips by hash before coverage. `null` means
  no pruning. `AppUITests` never appears: Tuist gives UI test targets no selective testing hash.
- `outcome` and `reason`. For `selected`, `run` maps each test that runs to its `reason` and
  `matched_path`, and `skip` maps each skipped test to `unaffected`. Tests in targets skipped by
  hash aren't listed. For `fallback`, `run_targets` are the targets that run whole.
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

Edits to `common/` change evidence and hashes. Update `baseline_evidence` and the affected
scenarios, re-measure the hash stage with `tuist hash selective-testing` at each checkout, and
run `scenarios.sh check` on a fresh build. Regenerate `xcodeproj/Shop.xcodeproj` when targets
change, and keep both variants' `Package.resolved` on the same TestCoverageAttribution version.
