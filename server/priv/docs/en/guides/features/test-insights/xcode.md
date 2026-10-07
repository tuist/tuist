---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Xcode test insights {#xcode-test-insights}

Tuist Test Insights gives you Xcode test analytics to monitor your test suite's health by identifying slow tests or quickly understanding failed CI runs. As your test suite grows, it becomes increasingly difficult to spot trends like gradually slowing tests or intermittent failures. Tuist Test Insights provides you with the visibility you need to maintain a fast and reliable test suite.

With Test Insights, you can answer questions such as:
- Have my tests become slower? Which ones?
- Which tests are flaky and need attention?
- Why did my CI run fail?

## Setup {#setup}

To start tracking your tests, you can leverage the `tuist inspect test` command by adding it to your scheme's test post-action:

![Post-action for inspecting tests](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

In case you're using [Mise](https://mise.jdx.dev/), your script will need to activate `tuist` in the post-action environment:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise & Project Paths**
>
> Your environment's `PATH` environment variable is not inherited by the scheme post action, and therefore you have to use Mise's absolute path,
> which will depend on how you installed Mise. Moreover, don't forget to inherit the build settings from a target in your project such that you
> can run Mise from the directory pointed to by $SRCROOT.

Your test runs are now tracked as long as you are logged in to your Tuist account. You can access your test insights in the Tuist dashboard and see how they evolve over time:

![Dashboard with test insights](/images/guides/features/build-insights/tests-dashboard.png)

Apart from overall trends, you can also dive deep into each individual test, such as when debugging failures or slow tests on the CI:

![Test detail](/images/guides/features/build-insights/test-detail.png)

## Generated projects {#generated-projects}

> [!NOTE]
> Auto-generated schemes automatically include the `tuist inspect test` post-action.

>
> If you are not interested in tracking test insights in your auto-generated schemes, disable them using the [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) generation option.

If you are using generated projects with custom schemes, you can set up post-actions for test insights:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

If you're not using Mise, your scripts can be simplified to:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## Continuous integration {#continuous-integration}

To track test insights on CI, you will need to ensure that your CI is <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

Additionally, you will either need to:
- Use the <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> command when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` invocation.

When `xcodebuild` tests your project without `-resultBundlePath`, the required result bundle files are not generated. The `tuist inspect test` post-action requires these files to analyze your tests.

## Per-test coverage {#per-test-coverage}

> [!IMPORTANT]
> **Early access**
>
> Code coverage in Test Insights is in early access. Collecting per-test coverage requires the `TUIST_FEATURE_FLAG_COVERAGE=1` and `TUIST_COVERAGE_EVIDENCE=1` environment variables when running `tuist test` or `tuist xcodebuild test` with code coverage enabled.

Xcode's code coverage tells you what a whole test run covered. To know which code each test executed, your unit test targets link the [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) package, which records the coverage counters each test moves. Tuist uses it so that a run that skips tests can reuse those tests' coverage from an earlier run. Per-test coverage is collected on macOS and the iOS simulator, and the package requires macOS 13 or iOS 16 as the deployment target of the test targets that link it.

### Generated projects {#per-test-coverage-generated-projects}

Declare the package in `Tuist/Package.swift`. Pin it to a minor version: it is pre-1.0, and minor versions can break.

```swift
let package = Package(
    name: "MyApp",
    dependencies: [
        .package(url: "https://github.com/tuist/TestCoverageAttribution", .upToNextMinor(from: "0.1.1")),
    ]
)
```

Then turn on `attributeToTests` in `Tuist.swift` and run `tuist install`:

```swift
let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(attributeToTests: true)),
    project: .tuist()
)
```

When generating, Tuist links `TestCoverageAttribution` into every unit test target. It never links it into apps, frameworks or UI test targets, whose tests drive the app in a separate process. Tuist also generates the package's targets as dynamic frameworks, overriding any `productTypes` you set for them: a static framework would be dropped by the linker in test targets that only use XCTest, since they reference nothing in it. Generation fails if the package isn't declared in `Tuist/Package.swift`.

### Other projects {#per-test-coverage-other-projects}

Add the package to your project and link the `TestCoverageAttribution` product to your unit test targets, as its [README](https://github.com/tuist/TestCoverageAttribution#installation) describes. If you link it statically, add `-ObjC` to the test targets' `OTHER_LDFLAGS`.

### Swift Testing {#per-test-coverage-swift-testing}

XCTest tests need nothing else: the package observes them as soon as the test bundle loads. Swift Testing has no observation center a library can join, so add the `.coverageAttribution` trait to your suites:

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution, .serialized)
struct CheckoutTests {
    @Test func appliesDiscount() { ... }
}
```

### Run tests serially {#per-test-coverage-serial-testing}

Coverage can only be attributed to a test when it runs alone in its process. A test that overlaps another is left out of per-test coverage. Use `.serialized` on Swift Testing suites, and pass `-parallel-testing-enabled NO` to `xcodebuild` for full attribution.
