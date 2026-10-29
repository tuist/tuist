---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Build insights · Features · Guides · Tuist",
  "description": "Track build analytics for a Tuist-generated Xcode project on the Tuist dashboard."
}
---
# 已生成嘅 Xcode 專案 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動生成嘅 scheme 會自動包含 `tuist inspect build` 後續動作。

>
> 如果你唔想喺已生成嘅 scheme 中追蹤構建洞察，可以使用 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 嚟停用。

如果你使用帶有自訂 scheme 嘅已生成專案，你需要自己添加後續動作。對於 [Mise](https://mise.jdx.dev/)：

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

如果你唔使用 Mise，你需要確保 `tuist` 喺 scheme 嘅環境中可用，因為 Xcode 後續動作唔會繼承你 shell 嘅 `PATH`。對於 [Homebrew](https://brew.sh/) 安裝：

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

## CI 中嘅構建洞察 {#continuous-integration}

要喺 CI 上追蹤構建洞察，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">驗證</.localized_link>。

對於由 Xcodebuild 驅動嘅 CI，你需要：
- 喺調用 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 添加到你嘅 `xcodebuild` 命令中。

如果冇 `-resultBundlePath`，就唔會生成所需嘅活動日誌同結果包，而 `tuist inspect build` 亦都無法分析構建。

## 機器指標 {#machine-metrics}

構建洞察可以包括喺構建期間捕獲嘅機器級別性能指標（CPU、記憶體、網絡同磁碟使用量）。要啟用此功能，請設置一個輕量級後台守護進程，持續採樣系統指標：

```bash
tuist setup insights
```

呢個會運行一個本地守護進程，喺後台採樣指標。數據會由 `tuist inspect build` 自動拾取並隨構建報告上傳。

> [!TIP]
> **Ci**
>
> 喺構建之前喺你嘅 CI 機器上運行 `tuist setup insights`，以同樣捕捉嗰度嘅機器指標。

要停止收集機器指標，請運行：

```bash
tuist teardown insights
```

呢個會卸載守護進程嘅 LaunchAgent，移除其 plist，並從 `~/.local/state` 刪除採樣嘅指標同守護進程日誌，因此後台唔會有任何東西繼續運行。


## 自訂元數據 {#custom-metadata}

你可以透過環境變量將元數據附加到構建，以改善篩選。

### 環境變量

| 變量 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 一個變量中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴係鍵。 |

### 示例

喺調用你嘅構建之前，喺 CI 或你嘅 shell 中設置呢啲值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
