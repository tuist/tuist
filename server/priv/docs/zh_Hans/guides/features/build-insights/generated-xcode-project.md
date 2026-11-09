---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板上跟踪由 Tuist 生成的 Xcode 项目的构建分析数据。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自动生成的方案会自动包含 `tuist inspect build` 后置操作。
>
> 如果你不想在生成的方案中跟踪构建洞察，可以使用 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 禁用它。

如果你在使用带有自定义方案的生成项目，需要自行添加后置操作。对于 [Mise](https://mise.jdx.dev/)：

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

如果你不使用 Mise，则需要确保 `tuist` 在方案的环境中可用，因为 Xcode 的后置操作不会继承你 shell 的 `PATH`。对于 [Homebrew](https://brew.sh/) 安装：

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

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
