---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板上追蹤由 Tuist 產生的 Xcode 專案的建置分析資料。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動產生的 Scheme 會自動包含 `tuist inspect build` 後置動作。

>
> 如果你不想在產生的 Scheme 中追蹤建置洞察，請使用 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 停用。

如果你使用帶有自訂 Scheme 的產生專案，需要自行新增後置動作。適用於 [Mise](https://mise.jdx.dev/)：

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

如果你未使用 Mise，由於 Xcode 後置動作不會繼承你 Shell 的 `PATH`，你需要確保 `tuist` 在 Scheme 的環境中可用。對於 [Homebrew](https://brew.sh/) 安裝：

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

## CI 中的建置洞察 {#continuous-integration}

若要在 CI 上追蹤建置洞察，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，你需要：
- 在叫用 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加入你的 `xcodebuild` 指令。

如果沒有 `-resultBundlePath`，就不會產生必要的活動記錄與結果套件，`tuist inspect build` 也無法分析建置。

## 機器指標 {#machine-metrics}

建置洞察可以包含在建置期間擷取的機器層級效能指標（CPU、記憶體、網路與磁碟使用量）。若要啟用此功能，請設定一個輕量的背景常駐程式，持續採樣系統指標：

```bash
tuist setup insights
```

這會執行一個在本機背景採樣指標的常駐程式。`tuist inspect build` 會自動抓取這些資料，並隨建置報告一起上傳。

> [!TIP]
> **Ci**
>
> 在建置前於你的 CI 機器上執行 `tuist setup insights`，以同時在那裡擷取機器指標。

若要停止收集機器指標，請執行：

```bash
tuist teardown insights
```

這會卸載常駐程式的 LaunchAgent、移除其 plist，並從 `~/.local/state` 刪除已採樣的指標與常駐程式記錄，因此背景不會留下任何仍在執行的程序。


## 自訂中繼資料 {#custom-metadata}

你可以透過環境變數將中繼資料附加到建置，以改善篩選效果。

### 環境變數

| 變數 | 格式 | 說明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 在單一變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值組，其中後綴為鍵。 |

### 範例

在叫用建置之前，於 CI 或你的 Shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
