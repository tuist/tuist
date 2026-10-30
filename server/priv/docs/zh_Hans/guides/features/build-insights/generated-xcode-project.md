---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板上跟踪由 Tuist 生成的 Xcode 项目的构建分析数据。"
}
---
# 生成的 Xcode 项目{#generated-xcode-project-build-insights}

> [!NOTE]
> 自动生成的 Scheme 会自动包含 `tuist inspect build` 后操作。

>
> 如果你不想在生成的 Scheme 中跟踪构建洞察，请使用 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 禁用它。

如果你在使用带有自定义 Scheme 的生成项目，需要自行添加后操作。对于 [Mise](https://mise.jdx.dev/)：

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

如果你不使用 Mise，需要确保 `tuist` 在 Scheme 的环境中可用，因为 Xcode 的后操作不会继承你 Shell 的 `PATH`。对于 [Homebrew](https://brew.sh/) 安装：

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

## CI 中的构建洞察{#continuous-integration}

要在 CI 上跟踪构建洞察，请确保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。

对于由 Xcodebuild 驱动的 CI，你需要：
- 在调用 `xcodebuild` 操作时使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 将 `-resultBundlePath` 添加到你的 `xcodebuild` 命令中。

如果没有 `-resultBundlePath`，则不会生成所需的活动日志和结果包，`tuist inspect build` 也无法分析构建。

## 机器指标{#machine-metrics}

构建洞察可以包含在构建期间捕获的机器级性能指标（CPU、内存、网络和磁盘使用情况）。要启用此功能，请设置一个轻量级的后台守护进程，持续采样系统指标：

```bash
tuist setup insights
```

这会运行一个本地守护进程，在后台采样指标。`tuist inspect build` 会自动获取这些数据，并随构建报告一起上传。

> [!TIP]
> **Ci**
>
> 在构建之前，在你的 CI 机器上运行 `tuist setup insights`，以便同样捕获那里的机器指标。

要停止收集机器指标，请运行：

```bash
tuist teardown insights
```

这会卸载守护进程的 LaunchAgent，移除其 plist，并从 `~/.local/state` 删除采样的指标和守护进程日志，因此不会有任何内容在后台继续运行。


## 自定义元数据{#custom-metadata}

你可以通过环境变量为构建附加元数据，以改进过滤。

### 环境变量

| 变量 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗号分隔 | 在一个变量中包含多个标签。 |
| `TUIST_BUILD_VALUE_*` | 单个值 | 键值对，其中后缀是键。 |

### 示例

在调用构建之前，在 CI 或你的 Shell 中设置这些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
