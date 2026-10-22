---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Code Coverage · Test Insights · Features · Guides · Tuist",
  "description": "Measure the code coverage of a Tuist-generated Xcode project per file and per commit, including the code the binary cache and selective testing skip."
}
---
# Generated Xcode project {#generated-xcode-project-code-coverage}

> [!WARNING]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights</.localized_link> configured (auto-generated schemes include the `tuist inspect test` post-action; custom schemes need it added).

> [!NOTE] EARLY ACCESS
> Code coverage is in early access. [Reach out](mailto:contact@tuist.dev) to turn it on for your account, and set `TUIST_FEATURE_FLAG_COVERAGE=1` wherever you run Tuist, on CI and on developers' machines. Without the variable, Tuist collects and uploads no coverage.

Code coverage tells you which lines of your code your tests executed. Tuist uploads the line coverage of every `tuist test` run and folds the runs of a commit into one figure, for the project, each target and each file. The dashboard's **Code Coverage** page shows it per commit and as a trend for each branch.

The figure stays accurate when Tuist skips work. Your targets from the <.localized_link href="/guides/features/cache/module-cache">binary cache</.localized_link> are built with coverage counters, so their code is measured like code built from source. And the tests <.localized_link href="/guides/features/selective-testing/generated-xcode-project">selective testing</.localized_link> skips can keep the coverage they had in an earlier run, with [test-level coverage](#test-level-coverage).

## Setup {#setup}

### Turn coverage on {#turn-coverage-on}

Turn coverage on in the generation options of your `Tuist.swift`:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

With the option on:

- The test action of every scheme Tuist generates collects coverage, and so does the test action of every scheme you define that leaves `coverage` unset. A scheme with `.options(coverage: false)` or `.options(coverage: true)` keeps its value, and test plans decide coverage themselves.
- Your project's own targets are read from and warmed into the binary cache with coverage counters in Debug configurations. See [How it works](#instrumented-binaries).

The `TUIST_COVERAGE_ENABLED` environment variable (`1` or `0`) takes precedence over the option. Set it for a whole environment, such as a CI workflow, rather than for a single command, so that the commands that warm the cache and the ones that read it agree.

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> The option changes the cache keys of your project's targets and the selective-testing hashes of its test targets. Use the same value on every machine that shares the cache, and don't derive it from the environment (for example from `Environment.isCI`). A run with coverage off doesn't reuse the binaries or the selective-testing results of runs with coverage on.

### Run your tests {#run-your-tests}

Run your tests with `tuist test`, as usual:

```sh
tuist test
```

Tuist uploads the coverage the run collected along with its test results. To upload test runs without their coverage, turn the upload off in `Tuist.swift`, or set `TUIST_COVERAGE_UPLOAD=0` for a single environment:

```swift
let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: false)),
    project: .tuist()
)
```

### Complete each commit on CI {#complete-each-commit}

A commit's coverage often comes from several jobs: one per scheme, per shard, or per platform. Tuist can't tell when the last of them has reported, so tell it. Once every test job for a commit has finished, run this in a job that depends on all of them:

```sh
tuist coverage complete
```

The command reads the commit from the checkout or from your CI provider; pass `--commit <sha>` to name another one. Until a commit is complete, its coverage shows as **In progress** and stays out of its branch's trend.

## Test-level coverage {#test-level-coverage}

Without more setup, Tuist knows what each run covered, but not which tests covered what. That's enough as long as every run executes every test. When selective testing or a skip leaves tests out, Tuist needs to know what those tests executed in an earlier run to carry their coverage forward, and without that the commit's coverage is **Incomplete**.

Test-level coverage records, for each test target and, where it can, each test, which files and lines it executed. It's optional, but you need it to get complete coverage with selective testing.

> [!NOTE] EARLY ACCESS
> Test-level coverage also needs `TUIST_COVERAGE_EVIDENCE=1` wherever your tests run.

### Link the package {#link-the-package}

Add the [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) package to `Tuist/Package.swift` and link it as a dynamic framework, so the linker keeps it in test targets that don't reference it:

```swift
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [
            "TestCoverageAttribution": .framework,
            "TestCoverageAttributionObserver": .framework,
        ]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(url: "https://github.com/tuist/TestCoverageAttribution", .upToNextMinor(from: "0.1.1")),
    ]
)
```

Then add it to your unit test targets. Never link it to an app target:

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["Tests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

XCTest tests need nothing else.

### Attribute Swift Testing suites {#swift-testing}

Swift Testing has no observation hook a library can join, so add the `.coverageAttribution` trait to your suites. It applies to every test and nested suite of the suite it's on:

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct CheckoutTests {
    @Test func appliesDiscount() { ... }
}
```

Suites without the trait still count toward what their test target executed.

### Limitations {#test-level-limitations}

- **Swift Testing tests that run in parallel can't be attributed one by one.** Attribution needs the tests of a process to run one at a time, and Swift Testing runs them in parallel by default. A test that runs alongside another counts only toward its suite and target. That's still enough to carry a whole target that selective testing skips. To attribute every test, turn parallel testing off for the run (`tuist test -- -parallel-testing-enabled NO`), which makes it longer.
- **Recording works on macOS and the iOS simulator**, not on devices.
- **UI tests record nothing about the app**, because the app's code runs in a process that doesn't link the package.

## How it works {#how-it-works}

### Instrumented binaries {#instrumented-binaries}

A target from the binary cache is a prebuilt binary, and a test run can only measure its code if the binary was built with coverage counters. With coverage on, the binary cache keeps an instrumented variant of your project's own targets, and every command reads and warms that variant:

- **Debug configurations** use the instrumented variant: `tuist cache` warms it, and `tuist generate` and `tuist test` read it.
- **Release configurations** always use the plain variant, so what you ship never carries coverage counters.
- **External packages** always use the plain variant. Tuist only measures your repository's code.

Warm the cache with coverage on, in the same environment as your test jobs, so that `tuist test` finds instrumented binaries. When a run collects coverage but gets your targets from the cache as plain binaries, Tuist warns you, and their code isn't measured. The <.localized_link href="/guides/features/cache/module-cache#code-coverage">module cache</.localized_link> documents the variants in detail.

### Paths across machines {#paths-across-machines}

Instrumented binaries record their source paths relative to the checkout they were built in, so a binary warmed on CI measures the right files on any developer's machine.

The <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache</.localized_link> works the same way through prefix mapping, which Tuist turns off by default in builds that collect coverage, because Xcode's own coverage report can't resolve mapped paths. On Xcode 27 and later, with `enableCaching` on, `prefixMapping: true` keeps it on, so coverage builds share compilation results across checkouts too:

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist's upload resolves the mapped paths, but Xcode's coverage report and `xccov` can leave those files out. See <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Coverage with prefix mapping</.localized_link>.

### Skipped tests {#skipped-tests}

When selective testing skips a test target, or a test is skipped through quarantine or `-skip-testing`, Tuist reuses the coverage those tests had in an earlier run, wherever it provably still applies:

- **A skipped target** takes its coverage from an earlier passing run of the target with the same selective-testing hash. The hash covers the target's sources, its tests and all its dependencies, so the same hash means the same tests over the same code.
- **A skipped test** takes its coverage from an earlier run in which the files the test executed were the same as in this commit.

Both need [test-level coverage](#test-level-coverage). Run the whole suite on your default branch regularly, without selective testing, so there's always a recent run to carry from:

```sh
tuist test --no-selective-testing
```

Once on every merge is ideal. Daily or weekly can be enough for a repository with few changes. Test-level coverage expires after 90 days.

### Complete and incomplete commits {#commit-status}

Each commit on the dashboard has a status:

| Status | Meaning |
| --- | --- |
| In progress | Runs have reported coverage, but `tuist coverage complete` hasn't run for the commit yet. |
| Complete | Every test of the commit's schemes ran or was carried forward. |
| Incomplete | Some coverage couldn't be determined, so the figure is a lower bound. |
| Not measured | No run reported coverage for the commit. |

A branch's trend only includes complete commits. A commit is incomplete when, for example:

- Tests were skipped that couldn't be carried forward: there's no test-level coverage or no earlier run for them, the files they executed changed since, or the commit changed files that affect every target, such as `Package.resolved`, `Project.swift` or an `.xcconfig`.
- A run took your targets from the binary cache as plain binaries.
- Every run of a scheme was narrowed with `-only-testing`.
- A scheme's coverage only came from CI runs on a checkout with uncommitted changes.

## Performance impact {#performance-impact}

We measured coverage on Tuist's own repository: a `tuist test` run of 49 test bundles and about 5,000 tests, from a cold build with every cache off. These are one project's numbers, not guarantees:

- **About 16 seconds per run (+2.4%)** on an 11-minute run. All of it comes after the tests finish: about 11 seconds for Xcode to write its coverage report into the result bundle, and about 5 seconds for Tuist to export the coverage.
- **No measurable change in build or test execution time.**
- **DerivedData grows by about 13%**, and the Debug binary-cache artifacts of the repository's targets by about 6%.
- **Release archives and Release binary-cache artifacts don't change.**
- **Test-level coverage** adds about 18 more seconds after the tests with XCTest only, and about 31 seconds with every Swift Testing suite attributed.

## Limitations {#limitations}

### Release builds of schemes that collect coverage {#release-builds}

When a scheme's test action collects coverage, Xcode also instruments the targets that `xcodebuild build` compiles from source for that scheme, in any configuration, Release included. `xcodebuild archive` ignores the setting, so archives are never instrumented. Distribute archives, or build Release products from a scheme with `.options(coverage: false)`.

### Other coverage tools {#other-coverage-tools}

`-enableCodeCoverage YES` only decides whether a run collects coverage, as in Xcode. It doesn't make Tuist read instrumented binaries from the cache, so use the `Tuist.swift` option or `TUIST_COVERAGE_ENABLED` instead.

Xcode's own coverage report, and the tools that read it, never include code that came from the binary cache. Tuist's upload measures it. To see a target's coverage in Xcode, focus it with `tuist generate <target>` so it builds from source.

## Querying coverage {#querying}

The `tuist coverage` commands read what the dashboard shows. Without `--commit`, they read the latest complete commit of `--branch`, or of your default branch:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

All of them accept `--json` for scripting. The same data is available to agents through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>.
