---
{
  "title": "Generated Projects Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track build analytics for Tuist generated projects in the Tuist dashboard."
}
---
# Generated projects build insights {#generated-projects-build-insights}

> [!NOTE]
> Auto-generated schemes automatically include the `tuist inspect build` post-action.

>
> If you do not want to track build insights in generated schemes, disable it using [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

If you are using generated projects with custom schemes, you need to add the post-action yourself. For [Mise](https://mise.jdx.dev/):

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

If you are not using Mise, you need to ensure `tuist` is available in the scheme's environment since Xcode post-actions don't inherit your shell's `PATH`. For [Homebrew](https://brew.sh/) installations:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            tuist inspect build
            """,
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## Build Insights in CI {#continuous-integration}

To track build insights on CI, make sure CI is <.localized_link href="/guides/integrations/continuous-integration#authentication">authenticated</.localized_link>.

For Xcodebuild-driven CI you need to:
- Use <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> when invoking `xcodebuild` actions.
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
