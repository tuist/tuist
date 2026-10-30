---
{
  "title": "生成嘅 Xcode 專案",
  "titleTemplate": ":title · 構建分析 · 功能 · 指南 · Tuist",
  "description": "喺 Tuist 儀表板追蹤由 Tuist 生成嘅 Xcode 專案嘅構建分析。"
}
---
# 已產生嘅 Xcode 專案 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動產生嘅 scheme 會自動包含 `tuist inspect build` 後置動作。

>
> 如果你唔想喺已產生嘅 scheme 追蹤建構洞察，可以透過 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 停用。

如果你使用帶有自訂 scheme 嘅已產生專案，你需要自行加入後置動作。對於 [Mise](https://mise.jdx.dev/)：

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

如果你冇用 Mise，你需要確保 `tuist` 喺 scheme 環境中可用，因為 Xcode 後置動作唔會繼承你 shell 嘅 `PATH`。對於 [Homebrew](https://brew.sh/) 安裝：

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

## CI 中嘅建構洞察 {#continuous-integration}

要喺 CI 追蹤建構洞察，請確保 CI 已 <.localized_link href="/guides/integrations/continuous-integration#authentication">認證</.localized_link>。

對於由 Xcodebuild 驅動嘅 CI，你需要：
- 叫用 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加入你嘅 `xcodebuild` 指令。

如果冇 `-resultBundlePath`，就唔會產生所需嘅活動日誌同結果套件，`tuist inspect build` 亦都無法分析建構。

## 機器指標 {#machine-metrics}

建構洞察可以包括喺建構期間捕獲嘅機器級別效能指標（CPU、記憶體、網絡同磁碟使用量）。要啟用呢個功能，請設置一個輕量級背景守護程序，持續採樣系統指標：

```bash
tuist setup insights
```

呢個會運行一個本地守護程序，喺背景採樣指標。數據會由 `tuist inspect build` 自動拾取並隨建構報告一齊上載。

> [!TIP]
> **Ci**
>
> 喺建構之前喺你嘅 CI 機器上運行 `tuist setup insights`，以同時捕獲嗰度嘅機器指標。

要停止收集機器指標，請運行：

```bash
tuist teardown insights
```

呢個會卸載守護程序嘅 LaunchAgent，移除其 plist，並從 `~/.local/state` 刪除已採樣嘅指標同守護程序日誌，確保背景冇任何東西繼續運行。


## 自訂元數據 {#custom-metadata}

你可以透過環境變數將元數據附加到建構，以改善篩選。

### 環境變數

| 變數 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 一個變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴為鍵。 |

### 範例

喺叫用你嘅建構之前，喺 CI 或你嘅 shell 中設置呢啲值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
