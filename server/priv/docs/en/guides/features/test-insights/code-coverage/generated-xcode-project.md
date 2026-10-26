---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Code Coverage · Test Insights · Features · Guides · Tuist",
  "description": "Measure the code coverage of a Tuist-generated Xcode project per file and per commit, including the code the binary cache and selective testing skip."
}
---
# Generated Xcode project {#generated-xcode-project-code-coverage}

> [!NOTE] EARLY ACCESS
> Code coverage is in early access. [Reach out](mailto:contact@tuist.dev) to turn it on for your account, and set `TUIST_FEATURE_FLAG_COVERAGE=1` wherever you run Tuist, on CI and on developers' machines. Without the variable, Tuist collects and uploads no coverage.

Code coverage tells you which lines of your code your tests executed. Tuist uploads the line coverage of every `tuist test` run and folds the runs of a commit into one figure, for the project, each target and each file. The dashboard's **Code Coverage** page shows it per commit and as a trend for each branch.

The figure stays accurate when Tuist skips work. Your targets from the <.localized_link href="/guides/features/cache/module-cache">binary cache</.localized_link> are built with coverage counters, so their code is measured like code built from source. And when <.localized_link href="/guides/features/selective-testing/generated-xcode-project">selective testing</.localized_link> skips a test target, the target keeps the coverage it had in an earlier run, through the [target-level coverage](#target-level-coverage) Tuist records on every run.

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

### Leave schemes out {#leave-schemes-out}

Some test suites don't belong in your coverage. Acceptance or end-to-end tests that drive your app or CLI from another process, for example, execute code coverage can't see, and collecting it only makes them slower. Turn coverage off in the test action of their scheme:

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

The scheme keeps coverage off whatever the `Tuist.swift` option or `TUIST_COVERAGE_ENABLED` say, and its runs don't count toward a commit's coverage. Coverage is collected per scheme, so to leave one test target out, move it to a scheme of its own.

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

### Separate build and test jobs {#separate-build-and-test-jobs}

When your test jobs run tests built in another job, through <.localized_link href="/guides/features/selective-testing/generated-xcode-project#separate-build-and-test-jobs">`tuist test --without-building`</.localized_link> or <.localized_link href="/guides/features/test-sharding/generated-xcode-project">test sharding</.localized_link>, pass `--derived-data-path` to each test job:

```sh
tuist test --without-building --shard-index 0 --derived-data-path .build/DerivedData
```

That's where Tuist finds the coverage the run collected. Without it, xcodebuild writes the coverage under a derived data folder Tuist can't locate, and Tuist falls back to Xcode's coverage report, which leaves out the code that came from the binary cache and records no target-level coverage.

### Complete each commit on CI {#complete-each-commit}

A commit's coverage often comes from several jobs: one per scheme, per shard, or per platform. Tuist can't tell when the last of them has reported, so tell it. Once every test job for a commit has finished, run this in a job that depends on all of them:

```sh
tuist coverage complete
```

The command reads the commit from the checkout or from your CI provider; pass `--commit <sha>` to name another one. Until a commit is complete, its coverage shows as **In progress** and stays out of its branch's trend.

### Run the whole suite on your default branch {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> Selective testing only keeps a commit's coverage complete if there's an earlier run to carry the skipped targets from. Schedule a run of every test, without selective testing, on your default branch:
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> Once on every merge is ideal. Daily or weekly can be enough for a repository with few changes. The recorded coverage expires after 90 days, so run it more often than that.

Carried coverage relies on full runs. They refresh every target's recorded coverage before it expires, and they give Tuist a recent state of the files a selective run doesn't build. The more a repository changes between full runs, the more often a selective run finds a file that changed since and its commit's coverage is **Incomplete**.

## Target-level coverage {#target-level-coverage}

A run's coverage says what the whole run executed, not what each test target executed. When selective testing skips a target, Tuist needs to know what that target executed in an earlier run to carry its coverage forward.

So on every run, Tuist also records which files and lines each test target executed. It reads them from the coverage Xcode writes for each test process, so there's nothing to link or configure. It's recorded on macOS and the iOS simulator, not on devices. UI tests record nothing about the app they drive, because the app's code runs in a process of its own.

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

Selective testing skips a test target when an earlier passing run already tested it with the same hash. The hash covers the target's sources, its tests and all its dependencies, so the same hash means the same tests over the same code. Tuist reuses the [target-level coverage](#target-level-coverage) that earlier run recorded for the target. If it recorded none, for example because coverage was off back then or the run is older than 90 days, there's nothing to carry and the commit is **Incomplete**.

A selective run also doesn't build every file. For the files it didn't compile, Tuist takes the lines from the nearest earlier full run, as long as the files haven't changed since. That's why the [full runs](#full-runs) on your default branch matter.

Tests you skip yourself, with `--skip-test-targets` or `-skip-testing`, aren't carried forward: a commit whose runs left them out is **Incomplete**, unless another run at the commit ran them. Tests that quarantine skips aren't part of the coverage at all: Tuist neither carries them nor marks the commit **Incomplete** for them.

### Complete and incomplete commits {#commit-status}

Each commit on the dashboard has a status:

| Status | Meaning |
| --- | --- |
| In progress | Runs have reported coverage, but `tuist coverage complete` hasn't run for the commit yet. |
| Complete | Every test of the commit's schemes ran or was carried forward. |
| Incomplete | Some coverage couldn't be determined, so the figure is a lower bound. |
| Not measured | No run reported coverage for the commit. |

A branch's trend only includes complete commits. A commit is incomplete when, for example:

- Selective testing skipped a target that couldn't be carried forward: the earlier run recorded no coverage for it, a file the selective run didn't build changed since the last full run, or the commit changed files that affect every target, such as `Package.resolved`, `Project.swift` or an `.xcconfig`.
- A run skipped tests with `--skip-test-targets` or `-skip-testing`, and no other run at the commit ran them.
- A run took your targets from the binary cache as plain binaries.
- Every run of a scheme was narrowed with `-only-testing`.
- A scheme's coverage only came from CI runs on a checkout with uncommitted changes.

## Performance impact {#performance-impact}

We measured coverage on Tuist's own repository: a `tuist test` run of 49 test bundles and about 5,000 tests, from a cold build with every cache off. These are one project's numbers, not guarantees:

- **About 16 seconds per run (+2.4%)** on an 11-minute run. All of it comes after the tests finish: about 11 seconds for Xcode to write its coverage report into the result bundle, and about 5 seconds for Tuist to export the coverage.
- **No measurable change in build or test execution time.**
- **DerivedData grows by about 13%**, and the Debug binary-cache artifacts of the repository's targets by about 6%.
- **Release archives and Release binary-cache artifacts don't change.**
- **Target-level coverage** adds about 2 seconds.

## Limitations {#limitations}

### Release builds of schemes that collect coverage {#release-builds}

When a scheme's test action collects coverage, Xcode also instruments the targets that `xcodebuild build` compiles from source for that scheme, in any configuration, Release included. `xcodebuild archive` ignores the setting, so archives are never instrumented. Distribute archives, or build Release products from a scheme with `.options(coverage: false)`.

### Other coverage tools {#other-coverage-tools}

`-enableCodeCoverage YES` only decides whether a run collects coverage, as in Xcode. It doesn't make Tuist read instrumented binaries from the cache, so use the `Tuist.swift` option or `TUIST_COVERAGE_ENABLED` instead.

Xcode's own coverage report, and the tools that read it, only include targets Xcode built in that run, never code that came from the binary cache. Tuist's upload measures both. If you want a target's coverage in Xcode's report, generate the project with that target built from source: `tuist generate MyTarget` keeps `MyTarget` as source and takes the rest from the cache.

## Querying coverage {#querying}

The `tuist coverage` commands read what the dashboard shows. Without `--commit`, they read the latest complete commit of `--branch`, or of your default branch:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

All of them accept `--json` for scripting. The same data is available to agents through the <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol server</.localized_link>.
