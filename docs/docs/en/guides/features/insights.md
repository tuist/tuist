---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# Insights {#insights}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

Working on large projects shouldn't feel like a chore. In fact, it should be as enjoyable as working on a project you started just two weeks ago. One of the reasons it is not is because as the project grows, the developer experience suffers. The build times increase and tests become slow and flaky. It's often easy to overlook these issues until it gets to a point where they become unbearable – however, at that point, it's difficult to address them. Tuist Insights provides you with the tools to monitor the health of your project and maintain a productive developer environment as your project scales.

In other words, Tuist Insights helps you to answer questions such as:
- Has the build time significantly increased in the last week?
- Have my tests become slower? Which ones?

::: info
<!-- -->
Tuist Insights are in early development.
<!-- -->
:::

## Builds {#builds}

While you probably have some metrics for the performance of CI workflows, you might not have the same visibility into the local development environment. However, local build times are one of the most important factors that contribute to the developer experience.

To start tracking local build times, you can leverage the `tuist inspect build` command by adding it to your scheme's post-action:

![Post-action for inspecting builds](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
We recommend setting the "Provide build settings from" to the executable or your main build target to enable Tuist to track the build configuration.
<!-- -->
:::

::: info
<!-- -->
If you are not using <LocalizedLink href="/guides/features/projects">generated projects</LocalizedLink>, the post-scheme action is not executed in case the build fails.
<!-- -->
:::
>
> An undocumented feature in Xcode allows you to execute it even in this case. Set the attribute `runPostActionsOnFailure` to `YES` in your scheme's `BuildAction` in the relevant `project.pbxproj` file as follows:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

In case you're using [Mise](https://mise.jdx.dev/), your script will need to activate `tuist` in the post-action environment:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
Your environment's `PATH` environment variable is not inherited by the scheme post action, and therefore you have to use Mise's absolute path,
which will depend on how you installed Mise. Moreover, don't forget to inherit the build settings from a target in your project such that you
can run Mise from the directory pointed to by $SRCROOT.
<!-- -->
:::


Your local builds are now tracked as long as you are logged in to your Tuist account. You can now access your build times in the Tuist dashboard and see how they evolve over time:


::: tip
<!-- -->
To quickly access the dashboard, run `tuist project show --web` from the CLI.
<!-- -->
:::

![Dashboard with build insights](/images/guides/features/insights/builds-dashboard.png)

## Tests {#tests}

In addition to tracking builds, you can also monitor your tests. Test insights help you identify slow tests or quickly understand failed CI runs.

To start tracking your tests, you can leverage the `tuist inspect test` command by adding it to your scheme's test post-action:

![Post-action for inspecting tests](/images/guides/features/insights/inspect-test-scheme-post-action.png)

In case you're using [Mise](https://mise.jdx.dev/), your script will need to activate `tuist` in the post-action environment:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
Your environment's `PATH` environment variable is not inherited by the scheme post action, and therefore you have to use Mise's absolute path,
which will depend on how you installed Mise. Moreover, don't forget to inherit the build settings from a target in your project such that you
can run Mise from the directory pointed to by $SRCROOT.
<!-- -->
:::

Your test runs are now tracked as long as you are logged in to your Tuist account. You can access your test insights in the Tuist dashboard and see how they evolve over time:

![Dashboard with test insights](/images/guides/features/insights/tests-dashboard.png)

Apart from overall trends, you can also dive deep into each individual test, such as when debugging failures or slow tests on the CI:

![Test detail](/images/guides/features/insights/test-detail.png)

## Generated projects {#generated-projects}

::: info
<!-- -->
Auto-generated schemes automatically include both `tuist inspect build` and `tuist inspect test` post-actions.
<!-- -->
:::
>
> If you are not interested in tracking insights in your auto-generated schemes, disable them using the <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink> and <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink> generation options.

If you are using generated projects with custom schemes, you can set up post-actions for both build and test insights:

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
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
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
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
),
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

To track build and test insights on CI, you will need to ensure that your CI is <LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>.

Additionally, you will either need to:
- Use the <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> command when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` invocation.

When `xcodebuild` builds or tests your project without `-resultBundlePath`, the required activity log and result bundle files are not generated. Both `tuist inspect build` and `tuist inspect test` post-actions require these files to analyze your builds and tests.
