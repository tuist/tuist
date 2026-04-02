---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Xcode test insights {#xcode-test-insights}

> [!WARNING]
> **Requirements**
>
> - A <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</TuistWeb.Docs.MarkdownComponents.localized_link>


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

To track test insights on CI, you will need to ensure that your CI is <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</TuistWeb.Docs.MarkdownComponents.localized_link>.

Additionally, you will either need to:
- Use the <TuistWeb.Docs.MarkdownComponents.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</TuistWeb.Docs.MarkdownComponents.localized_link> command when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` invocation.

When `xcodebuild` tests your project without `-resultBundlePath`, the required result bundle files are not generated. The `tuist inspect test` post-action requires these files to analyze your tests.
