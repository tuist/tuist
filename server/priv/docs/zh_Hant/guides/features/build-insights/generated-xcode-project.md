---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板上追蹤由 Tuist 產生的 Xcode 專案的建置分析資料。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動產生的方案會自動包含 `tuist inspect build` 後置動作。
>
> 如果你不想在產生的方案中追蹤建置洞察，請使用 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 停用。

如果你使用帶有自訂方案的產生專案，需要自行新增後置動作。適用於 [Mise](https://mise.jdx.dev/)：

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

如果你未使用 Mise，則需確保 `tuist` 在方案的環境中可用，因為 Xcode 後置動作不會繼承你 Shell 的 `PATH`。適用於 [Homebrew](https://brew.sh/) 安裝：

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
