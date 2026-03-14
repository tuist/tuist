---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# 构建洞察{#build-insights}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
<!-- -->
:::

处理大型项目不应让人感到像是在做苦差事。事实上，它应该像两周前刚开始的项目一样令人愉悦。
之所以并非如此，部分原因在于随着项目规模的扩大，开发者体验会受到影响。构建时间变长，测试变得缓慢且不稳定。这些问题往往容易被忽视，直到它们变得难以忍受——然而，到了那个时候，要解决它们就很难了。Tuist
Insights 为您提供工具，帮助您监控项目健康状况，并在项目扩展时维持高效的开发环境。

换句话说，Tuist Insights 能帮助您解答以下问题：
- 过去一周内，构建时间是否显著增加？
- 与本地开发相比，我的 CI 构建速度是否变慢了？

虽然您可能已掌握持续集成 (CI) 工作流的性能指标，但对本地开发环境的可见性可能并不充分。然而，本地构建时间是影响开发者体验的最重要因素之一。

要开始跟踪本地构建时间，您可以通过将以下命令添加到方案的 post-action 中，利用`tuist inspect build` 命令：

![构建检查后的操作](/images/guides/features/insights/inspect-build-scheme-post-action.png)

信息
<!-- -->
我们建议将“从以下位置获取构建设置”设置为可执行文件或您的主构建目标，以便 Tuist 能够跟踪构建配置。
<!-- -->
:::

信息
<!-- -->
如果您未使用
<LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>，则在构建失败时不会执行后处理操作。
<!-- -->
:::
> 
> ` ``
> Xcode中有一项未记录的功能，允许您即使在此情况下也能执行该操作。请在相关项目的.pbxproj文件中，于方案的`BuildAction中，将属性`runPostActionsOnFailure`
> 设置为`YES` ，具体操作如下：
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

若使用[Mise](https://mise.jdx.dev/)，脚本需在后处理环境中激活`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
您的环境变量 `PATH`（`` `）中的 ``` 路径不会被 scheme post 操作继承，因此必须使用 Mise
的绝对路径（具体路径取决于您的安装方式）。此外，请务必从项目目标继承构建设置，以便能从 `$SRCROOT` 指向的目录运行 Mise。
<!-- -->
:::


只要您登录了 Tuist 账户，您的本地构建情况就会被记录下来。现在，您可以在 Tuist 仪表盘中查看构建时间，并观察其随时间的变化趋势：


::: tip
<!-- -->
要快速访问仪表盘，请在命令行界面（CLI）中运行：`tuist project show --web` 。
<!-- -->
:::

![包含构建分析的仪表板](/images/guides/features/insights/builds-dashboard.png)

## 生成的项目 {#generated-projects}

信息
<!-- -->
自动生成的方案会自动包含`tuist inspect build` 后处理操作。
<!-- -->
:::
> 
> 如果您不希望在自动生成的方案中追踪洞察数据，请使用
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> 生成选项将其禁用。

如果您使用的是带有自定义方案的生成项目，可以为构建洞察设置后处理操作：

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

若未使用 Mise，脚本可简化为：

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

## 持续集成{#continuous-integration}

要在 CI 上追蹤建置分析資料，您需要確保您的 CI 已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">完成驗證</LocalizedLink>。

此外，您还需要：
- 调用`xcodebuild` 操作时，请使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 命令。
- `` 在调用 ``` 时添加 `xcodebuild` 参数 `-resultBundlePath` `。

当`xcodebuild` 在未指定`-resultBundlePath` 的情况下构建项目时，所需的活动日志和结果包文件将不会生成。`tuist
inspect build` 的后处理操作需要这些文件来分析您的构建。
