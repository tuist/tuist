---
{
  "title": "Xcode 测试洞察",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 测试洞察跟踪 Xcode 测试分析数据，识别缓慢和不稳定测试。"
}
---
# Xcode 测试洞察 {#xcode-test-insights}

Tuist Test Insights 提供 Xcode 测试分析，帮助你通过识别缓慢测试或快速理解失败的 CI 运行来监控测试套件的健康状况。随着测试套件的增长，越来越难以发现诸如测试逐渐变慢或间歇性失败等趋势。Tuist Test Insights 为你提供所需的可见性，以维护快速且可靠的测试套件。

借助 Test Insights，你可以回答以下问题：
- 我的测试是否变慢了？哪些测试？
- 哪些测试不稳定并需要关注？
- 为什么我的 CI 运行失败？

## 设置 {#setup}

要开始跟踪你的测试，可以将 `tuist inspect test` 命令添加到方案的测试后操作中：

![用于检查测试的后操作](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

如果你使用的是 [Mise](https://mise.jdx.dev/)，则需要在后操作环境中激活 `tuist`：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise 与项目路径**
>
> 你的环境中的 `PATH` 环境变量不会被方案后操作继承，因此你必须使用 Mise 的绝对路径，具体取决于你安装 Mise 的方式。此外，请记得从项目中的某个目标继承构建设置，以便你可以从 $SRCROOT 指向的目录运行 Mise。

只要你登录了 Tuist 账户，你的测试运行就会被跟踪。你可以在 Tuist 仪表板中访问测试洞察，并查看它们随时间的变化：

![包含测试洞察的仪表板](/images/guides/features/build-insights/tests-dashboard.png)

除了整体趋势外，你还可以深入查看每个单独的测试，例如在 CI 上调试失败或缓慢测试时：

![测试详情](/images/guides/features/build-insights/test-detail.png)

## 生成的项目 {#generated-projects}

> [!NOTE]
> 自动生成的方案会自动包含 `tuist inspect test` 后操作。
>
> 如果你不想在自动生成的方案中跟踪测试洞察，可以使用 [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 生成选项禁用它们。

如果你使用的是带有自定义方案的生成项目，可以为测试洞察设置后操作：

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

如果你不使用 Mise，可以将脚本简化为：

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

## 持续集成 {#continuous-integration}

要在 CI 上跟踪测试洞察，你需要确保你的 CI 已<.localized_link href="/guides/server/authentication#continuous-integration">认证</.localized_link>。

此外，你还需要：
- 在调用 `xcodebuild` 操作时使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> 命令。
- 将 `-resultBundlePath` 添加到你的 `xcodebuild` 调用中。

当 `xcodebuild` 在没有 `-resultBundlePath` 的情况下测试你的项目时，不会生成所需的结果包文件。`tuist inspect test` 后操作需要这些文件来分析你的测试。

### Git 历史 {#git-history}

在 CI 上，Tuist 还会上传检出仓库的提交历史：提交 SHA、其父提交、提交日期以及运行及其拉取请求的基础分支所在的分支。不会上传文件内容、提交消息或作者信息。这告诉 Tuist 哪些提交进入了你的默认分支，例如合并队列测试过的提交。Tuist 读取检出仓库已有的历史，如果检出仓库没有基础分支，则会向远程仓库请求其最新提交（`git ls-remote`）。除代码覆盖率外，它不会获取历史。启用代码覆盖率时，会加深浅层检出，但不包含文件内容，以找到拉取请求的分叉点并到达 Tuist 已有的提交，因此永远不会上传没有父提交的提交。

| 变量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不读取或上传任何 Git 历史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 仅读取检出仓库，不与远程仓库通信。 |
