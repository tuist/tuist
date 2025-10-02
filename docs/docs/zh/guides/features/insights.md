---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# 见解 {#insights｝

> [！重要]要求
> - <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>

在大型项目上工作不应该感觉是一件苦差事。事实上，它应该和两周前刚刚开始的项目一样令人愉快。但事实并非如此，原因之一是随着项目的增长，开发人员的体验会受到影响。构建时间增加，测试变得缓慢而不稳定。人们往往很容易忽视这些问题，直到它们变得难以忍受--然而，到了那个时候，就很难解决这些问题了。Tuist
Insights 可为您提供各种工具来监控项目的健康状况，并在项目扩展过程中保持高效的开发人员环境。

换句话说，Tuist Insights 可以帮助您回答以下问题：
- 在过去一周中，建造时间是否有明显增加？
- 我的测试速度变慢了吗？哪些变慢了？

> [注] Tuist Insights 处于早期开发阶段。

## 构建 {#builds｝

虽然您可能对 CI 工作流的性能有一定的衡量标准，但对本地开发环境的可视性可能不尽相同。然而，本地构建时间是影响开发人员体验的最重要因素之一。

要开始跟踪本地构建时间，可以利用`tuist inspect build` 命令，将其添加到方案的后期行动中：

![检查构建的后期行动](/images/guides/features/insights/inspect-build-scheme-post-action.png)。

> [注意] 我们建议将 "从执行文件或主要构建目标提供构建设置 "设置为可执行文件或主要构建目标，以便 Tuist 跟踪构建配置。

> [！注意] 如果不使用 <LocalizedLink href="/guides/features/projects">
> 生成的项目</LocalizedLink>，则在构建失败时不会执行后方案操作。
> 
> 即使在这种情况下，Xcode 中一个未注明的功能也允许您执行它。`` 在相关的`project.pbxproj`
> 文件中，将`runPostActionsOnFailure` 属性设置为`YES` ：
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

如果您使用的是 [Mise](https://mise.jdx.dev/)，您的脚本需要在行动后环境中激活`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

tuist inspect build
```


现在，只要您登录 Tuist 帐户，您的本地构建就会被跟踪。您现在可以在 Tuist 面板中访问您的构建时间，并查看它们随时间的变化情况：


> [提示] 要快速访问仪表板，请从 CLI 运行`tuist project show --web` 。

!!!!!!!!!![仪表板，包含构建见解](/images/guides/features/insights/builds-dashboard.png)。

## 生成的项目 {#generated-projects}

> [！注意] 自动生成的方案会自动包含`tuist 检查构建` 行动后。
> 
> 如果不想在自动生成的方案中跟踪构建洞察，请使用
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> 生成选项禁用它们。

如果使用的是生成的项目，则可以使用自定义方案设置自定义
<LocalizedLink href="references/project-description/structs/buildaction#postactions">
建站后操作</LocalizedLink>，例如

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
                        """,
                        target: "MyApp"
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

如果不使用 Mise，脚本可简化为：

```swift
.postAction(
    name: "Inspect Build",
    script: "tuist inspect build",
    execution: .always
)
```

## 持续集成 {#continuous-integration｝

要在 CI 上跟踪构建时间，您需要确保您的 CI 已通过
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">
验证</LocalizedLink>。

此外，您还需要
- 在调用`xcodebuild` 操作时，使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 命令。
- 在`xcodebuild` 调用中添加`-resultBundlePath` 。

当`xcodebuild` 在没有`-resultBundlePath` 的情况下构建您的项目时，不会生成`.xcactivitylog` 文件。但`tuist
inspect build` 后操作要求生成该文件，以分析您的构建。
