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

处理大型项目不应令人感到乏味。事实上，它应该像两周前刚启动的项目那样充满乐趣。
开发体验恶化的根源在于：项目规模扩大时，构建时间延长，测试变得迟缓且不稳定。这些问题往往在达到忍无可忍的程度前容易被忽视——而一旦发展到这种地步，解决起来就困难重重。Tuist
Insights 为您提供工具，助您监控项目健康状况，在项目扩展过程中维持高效的开发环境。

换言之，Tuist Insights 助您解答诸如：
- 上周构建时间是否显著增加？
- 我的构建在CI环境中是否比本地开发慢？

虽然您可能已建立持续集成工作流的性能指标体系，但本地开发环境的可视化程度可能存在不足。然而，本地构建时长正是影响开发者体验的核心要素之一。

要开始追踪本地构建时间，可将`tuist inspect build` 命令添加至方案的后处理操作中：

![检查构建后的操作](/images/guides/features/insights/inspect-build-scheme-post-action.png)

信息
<!-- -->
建议将"提供构建设置来源"设置为可执行文件或您的主构建目标，以便Tuist能够追踪构建配置。
<!-- -->
:::

信息
<!-- -->
若未使用<LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>，则构建失败时不会执行后方案操作。
<!-- -->
:::
> 
> ` ````
> Xcode中存在一项未文档化的功能，即使在此情况下仍可执行。在相关项目（`）的项目文件（project.pbxproj）中，于方案（scheme）的构建设置（`）下，将`的runPostActionsOnFailure属性设置为YES，具体操作如下：
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


只要登录Tuist账户，您的本地构建进度将自动追踪。您现在可通过Tuist仪表盘查看构建时间，并追踪其随时间的变化趋势：


::: tip
<!-- -->
要快速访问仪表板，请在命令行界面运行：`tuist project show --web`
<!-- -->
:::

![包含构建洞察的仪表板](/images/guides/features/insights/builds-dashboard.png)

## 生成的项目 {#generated-projects}

信息
<!-- -->
自动生成的方案会自动包含`tuist inspect build` 后处理操作。
<!-- -->
:::
> 
> 若您不希望在自动生成的架构中追踪洞察数据，请通过
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> 生成功能选项禁用该功能。

若使用自定义方案生成的项目，可为构建洞察设置后置操作：

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

要在持续集成中追踪构建洞察，您需要确保您的持续集成已完成<LocalizedLink href="/guides/integrations/continuous-integration#authentication">身份验证</LocalizedLink>。

此外，您还需要：
- 调用`xcodebuild` 操作时，请使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 命令。
- `在调用 ``` 时添加 `xcodebuild` ` 参数 `-resultBundlePath` `。

当执行 ``` 并使用 `xcodebuild` ` 构建项目时，若未指定 ``` 及
`-resultBundlePath``，则不会生成必需的活动日志和结果包文件。`的 `tuist inspect build` `
后置操作需要这些文件来分析构建结果。
