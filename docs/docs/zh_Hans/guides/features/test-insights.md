---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# 测试洞察{#test-insights}

警告要求
<!-- -->
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
<!-- -->
:::

测试洞察功能可帮助您监控测试套件的健康状况，识别运行缓慢的测试或快速理解失败的持续集成运行。随着测试套件规模扩大，发现测试逐渐变慢或间歇性失败等趋势将变得越来越困难。Tuist
测试洞察为您提供所需的可视性，助您维护快速可靠的测试套件。

借助测试洞察功能，您可以解答以下问题：
- 我的测试是否变慢了？具体是哪些测试？
- 哪些测试结果不稳定需要关注？
- 为什么我的CI运行失败？

## 设置{#setup}

要开始跟踪测试，可将`tuist inspect test` 命令添加至方案的测试后处理操作中：

![检查测试后的操作](/images/guides/features/insights/inspect-test-scheme-post-action.png)

若使用[Mise](https://mise.jdx.dev/)，脚本需在后处理环境中激活`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
您的环境变量 `PATH`（`` `）中的 ``` 路径不会被 scheme post 操作继承，因此必须使用 Mise
的绝对路径（具体路径取决于您的安装方式）。此外，请务必从项目目标继承构建设置，以便能从 `$SRCROOT` 指向的目录运行 Mise。
<!-- -->
:::

只要登录Tuist账户，您的测试运行情况就会被持续追踪。您可在Tuist仪表盘查看测试洞察，并观察其随时间的变化趋势：

![测试洞察仪表盘](/images/guides/features/insights/tests-dashboard.png)

除整体趋势外，您还可深入分析每个单独测试，例如在CI环境中排查失败或缓慢的测试时：

![测试详情](/images/guides/features/insights/test-detail.png)

## 生成的项目 {#generated-projects}

信息
<!-- -->
自动生成的方案会自动包含`tuist inspect test` 后置操作。
<!-- -->
:::
> 
> 若您不希望在自动生成的方案中追踪测试洞察，可通过
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>
> 生成选项禁用该功能。

若使用自定义方案的生成项目，可为测试洞察设置后置操作：

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
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

若未使用 Mise，脚本可简化为：

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## 持续集成{#continuous-integration}

要在持续集成（CI）中追踪测试洞察，您需要确保您的CI已<LocalizedLink href="/guides/integrations/continuous-integration#authentication">完成身份验证</LocalizedLink>。

此外，您还需要：
- 调用`xcodebuild` 操作时，请使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 命令。
- `在调用 ``` 时添加 `xcodebuild` ` 参数 `-resultBundlePath` `。

` `` 当执行 ``` 时，若 `xcodebuild` 通过 `` ` 测试项目却未指定 ``` 参数，则不会生成必需的结果包文件。而 `tuist
inspect test` 的 `post-action` 阶段（详见 `
