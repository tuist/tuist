---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode build insights {#xcode-build-insights}

Working on large projects should not require rebuilding the same code repeatedly. Tuist Build Insights lets you track build analytics so you can identify trends before local and CI build times become bottlenecks.

Build insights are driven by the `tuist inspect build` command, typically added to your scheme's post-action.

To start tracking local build times, you can leverage the `tuist inspect build` command by adding it to your scheme's post-action:

![Post-action for inspecting builds](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> Set the "Provide build settings from" field to the executable or your main build target to capture build configuration.

> [!NOTE]
> The post-scheme action is not executed when the build fails.
>
> You can execute it in that case by setting `runPostActionsOnFailure` to `YES` on the `<BuildAction>` element of the scheme's `.xcscheme` file:
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
> **Mise path resolution**
>
> Your environment's `PATH` is not inherited by the scheme post action, so use Mise's absolute path. This depends on how you installed Mise. Build settings should be inherited from a target so `mise` can run from `$SRCROOT`.

For [Homebrew](https://brew.sh/), add the Homebrew paths to the post-action environment:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Once logged in, local builds are tracked and available from the Tuist dashboard:

> [!TIP]
> To quickly access the dashboard, run `tuist project show --web` from the CLI.

![Dashboard with build insights](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
