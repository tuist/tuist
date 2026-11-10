---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Build insights · Features · Guides · Tuist",
  "description": "Track build analytics for a Tuist-generated Xcode project on the Tuist dashboard."
}
---
# Generated Xcode project {#generated-xcode-project-build-insights}

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

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
