---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 建構洞察 · 功能 · 指南 · Tuist",
  "description": "喺 Tuist 儀表板追蹤由 Tuist 生成嘅 Xcode 專案嘅建構分析數據。"
}
---
# 已生成嘅 Xcode 項目 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動生成嘅 Scheme 會自動包含 `tuist inspect build` 後置動作。
>
> 如果你唔想喺已生成嘅 Scheme 中追蹤構建洞察，可以透過 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 停用。

如果你使用帶有自訂 Scheme 嘅已生成項目，你需要自行加入後置動作。對於 [Mise](https://mise.jdx.dev/)：

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

如果你無使用 Mise，你需要確保 `tuist` 喺 Scheme 嘅環境中可用，因為 Xcode 後置動作唔會繼承你 Shell 嘅 `PATH`。對於 [Homebrew](https://brew.sh/) 安裝：

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
