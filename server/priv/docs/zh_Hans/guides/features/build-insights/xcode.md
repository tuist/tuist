---
{
  "title": "Xcode 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Xcode 构建分析，以监控本地和 CI 构建性能。"
}
---
# Xcode 构建洞察 {#xcode-build-insights}

开发大型项目不应要求反复重新构建相同的代码。Tuist Build Insights 让你能够跟踪构建分析数据，以便在本地和 CI 构建时间成为瓶颈之前识别趋势。

构建洞察由 `tuist inspect build` 命令驱动，该命令通常添加到你的 Scheme 的后置操作中。

要开始跟踪本地构建时间，你可以利用 `tuist inspect build` 命令，将其添加到你的 Scheme 的后置操作中：

![用于检查构建的后置操作](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 将“Provide build settings from”字段设置为可执行文件或你的主构建目标，以捕获构建配置。

> [!NOTE]
> 当构建失败时，不会执行 Scheme 后置操作。
>
> 在这种情况下，你可以通过在 Scheme 的 `.xcscheme` 文件的 `<BuildAction>` 元素上将 `runPostActionsOnFailure` 设置为 `YES` 来执行它：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

对于 [Mise](https://mise.jdx.dev/)，在后置操作环境中激活 `tuist`：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 路径解析**
>
> 你的环境中的 `PATH` 不会被 Scheme 后置操作继承，因此请使用 Mise 的绝对路径。这取决于你如何安装 Mise。构建设置应从目标继承，以便 `mise` 可以从 `$SRCROOT` 运行。

对于 [Homebrew](https://brew.sh/)，将 Homebrew 路径添加到后置操作环境中：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

登录后，本地构建将被跟踪并可在 Tuist 仪表板中查看：

> [!TIP]
> 要快速访问仪表板，请从 CLI 运行 `tuist project show --web`。

![带有构建洞察的仪表板](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
