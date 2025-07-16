---
title: Insights
titleTemplate: :title · Features · Guides · Tuist
description: Get insights into your projects to maintain a product developer environment.
---

# Insights {#insights}

> [!IMPORTANT] REQUIREMENTS
>
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>

Working on large projects shouldn't feel like a chore. In fact, it should be as enjoyable as working on a project you started just two weeks ago. One of the reasons it is not is because as the project grows, the developer experience suffers. The build times increase and tests become slow and flaky. It's often easy to overlook these issues until it gets to a point where they become unbearable – however, at that point, it's difficult to address them. Tuist Insights provides you with the tools to monitor the health of your project and maintain a productive developer environment as your project scales.

In other words, Tuist Insights helps you to anwer questions such as:

- Has the build time significantly increased in the last week?
- Have my tests become slower? Which ones?

> [!NOTE]
> Tuist Insights are in early development.

## Builds {#builds}

While you probably have some metrics for the performance of CI workflows, you might not have the same visibility into the local development environment. However, local build times are one of the most important factors that contribute to the developer experience.

To start tracking local build times, you can leverage the `tuist inspect build` command by adding it to your scheme's post-action:

![Post-action for inspecting builds](/images/guides/features/insights/inspect-build-scheme-post-action.png)

In case you're using [Mise](https://mise.jdx.dev/), your script will need to activate `tuist` in the post-action environment:

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

tuist inspect build
```

Your local builds are now tracked as long as you are logged in to your Tuist account. You can now access your build times in the Tuist dashboard and see how they evolve over time:

> [!TIP]
> To quickly access the dashboard, run `tuist project show --web` from the CLI.

![Dashboard with build insights](/images/guides/features/insights/builds-dashboard.png)

## Generated projects {#generated-projects}

> [!NOTE]
> Auto-generated schemes automatically include the `tuist inspect build` post-action.
>
> If you are not interested in tracking build insights in your auto-generated schemes, disable them using the <LocalizedLink href="references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink> generation option.

If you are using generated projects, you can set up a custom <LocalizedLink href="references/project-description/structs/buildaction#postactions">build post-action</LocalizedLink> using a custom scheme, such as:

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
                        name: "Inspect Build",
                        scriptText: """
                        eval \"$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)\"
                        tuist inspect build
                        """
                    )
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .testAction(targets: ["MyAppTests"]),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

If you're not using Mise, your script can be simplified to just:

```swift
.postAction(
    name: "Inspect Build",
    script: "tuist inspect build",
    execution: .always
)
```

## Continuous integration {#continuous-integration}

To track build times also on the CI, you will need to ensure that your CI is <LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>.

Additionally, you will either need to:

- Use the <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> command when invoking `xcodebuild` actions.
- Add `-resultBundlePath` to your `xcodebuild` invocation.

When `xcodebuild` builds your project without `-resultBundlePath`, the `.xcactivitylog` file is not generated. But the `tuist inspect build` post-action requires that file to be generated to analyze your build.
