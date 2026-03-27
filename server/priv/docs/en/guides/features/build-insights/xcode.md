---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode build insights {#xcode-build-insights}

> [!WARNING]
> **Requirements**
>
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
> - Tuist CLI 4.138.1 or later
> - A Xcode project


Working on large projects should not require rebuilding the same code repeatedly. Tuist Build Insights lets you track build analytics so you can identify trends before local and CI build times become bottlenecks.

Build insights are driven by the `tuist inspect build` command, typically added to your scheme's post-action.

To start tracking local build times, you can leverage the `tuist inspect build` command by adding it to your scheme's post-action:

![Post-action for inspecting builds](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Set the "Provide build settings from" field to the executable or your main build target to capture build configuration.


> [!NOTE]
> If you are not using <LocalizedLink href="/guides/features/projects">generated projects</LocalizedLink>, the post-scheme action is not executed when the build fails.

>
> You can execute it in that case by setting `runPostActionsOnFailure` to `YES` in the relevant `project.pbxproj` `BuildAction`:
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

For [Mise](https://mise.jdx.dev/), activate `tuist` in the post-action environment:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise & Project Paths**
>
> Your environment's `PATH` is not inherited by the scheme post action, so use Mise's absolute path. This depends on how you installed Mise. Build settings should be inherited from a target so `mise` can run from `$SRCROOT`.


Once logged in, local builds are tracked and available from the Tuist dashboard:

> [!TIP]
> To quickly access the dashboard, run `tuist project show --web` from the CLI.


![Dashboard with build insights](/images/guides/features/build-insights/builds-dashboard.png)

## Generated projects {#generated-projects}

> [!NOTE]
> Auto-generated schemes automatically include the `tuist inspect build` post-action.

>
> If you do not want to track build insights in generated schemes, disable it using [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

If you are using generated projects with custom schemes, add post-actions:

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
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

If you are not using Mise, simplify to:

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

## Build Insights in CI {#continuous-integration}

To track build insights on CI, make sure CI is <LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>.

For Xcodebuild-driven CI you need to:
- Use <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` command.

Without `-resultBundlePath`, required activity logs and result bundles are not generated and `tuist inspect build` cannot analyze the build.

## Machine metrics {#machine-metrics}

Build insights can include machine-level performance metrics (CPU, memory, network, and disk usage) captured during the build. To enable this, set up a lightweight background daemon that continuously samples system metrics:

```bash
tuist setup insights
```

This runs a local daemon that samples metrics in the background. The data is picked up automatically by `tuist inspect build` and uploaded with the build report.

> [!TIP]
> **Ci**
>
> Run `tuist setup insights` on your CI machines before building to capture machine metrics there as well.


## Custom metadata {#custom-metadata}

You can attach metadata to builds with environment variables to improve filtering.

### Environment variables

| Variable | Format | Description |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Comma-separated | Multiple tags in one variable. |
| `TUIST_BUILD_VALUE_*` | Single value | Key-value pair where suffix is the key. |

### Examples

Set these values in CI or your shell before invoking your build:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```