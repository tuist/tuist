---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get Xcode build analytics with Tuist Build Insights to maintain a productive developer environment."
}
---
# Build Insights {#build-insights}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
<!-- -->
:::

Working on large projects shouldn't feel like a chore. In fact, it should be as enjoyable as working on a project you started just two weeks ago. One of the reasons it is not is because as the project grows, the developer experience suffers. The build times increase and tests become slow and flaky. It's often easy to overlook these issues until it gets to a point where they become unbearable – however, at that point, it's difficult to address them. Tuist Build Insights provides Xcode build analytics to monitor the health of your project and maintain a productive developer environment as your project scales.

In other words, Tuist Insights helps you to answer questions such as:
- Has the build time significantly increased in the last week?
- Are my builds slower on CI compared to local development?

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

## Generated projects {#generated-projects}

::: info
<!-- -->
Auto-generated schemes automatically include the `tuist inspect build` post-action.
<!-- -->
:::
>
> If you are not interested in tracking insights in your auto-generated schemes, disable them using the <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink> generation option.

If you are using generated projects with custom schemes, you can set up post-actions for build insights:

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
)
```

## Continuous integration {#continuous-integration}

To track build insights on CI, you will need to ensure that your CI is <LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>.

Additionally, you will either need to:
- Use the <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> command when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` invocation.

When `xcodebuild` builds your project without `-resultBundlePath`, the required activity log and result bundle files are not generated. The `tuist inspect build` post-action requires these files to analyze your builds.

## Custom metadata {#custom-metadata}

You can attach custom metadata to your builds using environment variables. This is useful for filtering and categorizing builds in the dashboard, or correlating them with external systems like issue trackers or CI pipelines.

### Environment variables

| Variable | Format | Description |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Comma-separated | Multiple tags in a single variable |
| `TUIST_BUILD_VALUE_*` | Single value | Key-value pair (suffix becomes the key) |

### Examples

The post-action script inherits environment variables from the system. Set these variables in your CI configuration or shell environment:

```sh
# Using TUIST_BUILD_TAGS for multiple tags
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
# Using TUIST_BUILD_VALUE_* for key-value pairs
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
