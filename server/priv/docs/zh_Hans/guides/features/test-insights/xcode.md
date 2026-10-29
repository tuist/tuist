---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Xcode 测试洞察 {#xcode-test-insights}

Tuist Test Insights 为您提供 Xcode 测试分析，通过识别缓慢的测试或快速理解失败的 CI 运行来监控您的测试套件的健康状况。随着您的测试套件的增长，越来越难以发现诸如测试逐渐变慢或间歇性失败等趋势。Tuist Test Insights 为您提供所需的可见性，以维护快速且可靠的测试套件。

借助 Test Insights，您可以回答以下问题：
- 我的测试变慢了吗？哪些测试？
- 哪些测试不稳定且需要关注？
- 为什么我的 CI 运行失败了？

## 设置 {#setup}

要开始跟踪您的测试，您可以利用 `tuist inspect test` 命令，将其添加到方案的测试后操作中：

![检查测试的后操作](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

如果您使用 [Mise](https://mise.jdx.dev/)，则需要在后操作环境中激活 `tuist`：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise 与项目路径**
>
> 您环境的 `PATH` 环境变量不会被方案后操作继承，因此您必须使用 Mise 的绝对路径，这取决于您如何安装 Mise。此外，不要忘记从项目中的目标继承构建设置，以便您可以从 $SRCROOT 指向的目录运行 Mise。

只要您登录到 Tuist 账户，您的测试运行就会被跟踪。您可以在 Tuist 仪表板中访问您的测试洞察，并查看它们随时间的变化：

![带有测试洞察的仪表板](/images/guides/features/build-insights/tests-dashboard.png)

除了整体趋势外，您还可以深入查看每个单独的测试，例如在 CI 上调试失败或缓慢的测试时：

![测试详情](/images/guides/features/build-insights/test-detail.png)

## 生成的项目 {#generated-projects}

> [!NOTE]
> 自动生成的方案会自动包含 `tuist inspect test` 后操作。

>
> 如果您对在自动生成的方案中跟踪测试洞察不感兴趣，请使用 [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 生成选项禁用它们。

如果您使用带有自定义方案的生成项目，可以为测试洞察设置后操作：

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

如果您不使用 Mise，您的脚本可以简化为：

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

要在 CI 上跟踪测试洞察，您需要确保您的 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。

此外，您需要：
- 在调用 `xcodebuild` 操作时使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> 命令。
- 将 `-resultBundlePath` 添加到您的 `xcodebuild` 调用中。

当 `xcodebuild` 在没有 `-resultBundlePath` 的情况下测试您的项目时，不会生成所需的结果包文件。`tuist inspect test` 后操作需要这些文件来分析您的测试。

### Git 历史 {#git-history}

在 CI 上，Tuist 还会上传检出的提交历史：提交 SHA、其父提交、提交日期以及运行及其拉取请求的基础分支所在的分支。不会上传文件内容、提交消息或作者。它告诉 Tuist 哪些提交合并到了您的默认分支，例如合并队列测试的那些提交。Tuist 读取检出已有的历史，当检出没有基础分支时，会向远程询问其最新提交 (`git ls-remote`)。除代码覆盖率外，它不会获取历史。

| 变量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不读取或上传任何 Git 历史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 仅读取检出，不与远程联系。 |
