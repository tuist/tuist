---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Build insights · Features · Guides · Tuist",
  "description": "Track build analytics for a Tuist-generated Xcode project on the Tuist dashboard."
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-build-insights}

> [!NOTE]
> 自動產生的 Scheme 會自動包含 `tuist inspect build` 後置動作。

>
> 如果您不想在產生的 Scheme 中追蹤建構洞察，請使用 [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 停用。

如果您使用的是帶有自訂 Scheme 的產生專案，您需要自行新增後置動作。對於 [Mise](https://mise.jdx.dev/)：

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

如果您未使用 Mise，則需要確保 `tuist` 在 Scheme 的環境中可用，因為 Xcode 後置動作不會繼承您 Shell 的 `PATH`。對於 [Homebrew](https://brew.sh/) 安裝：

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

## CI 中的建構洞察 {#continuous-integration}

若要在 CI 上追蹤建構洞察，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，您需要：
- 在叫用 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加入您的 `xcodebuild` 指令。

若沒有 `-resultBundlePath`，將不會產生必要的活動記錄和結果套件，且 `tuist inspect build` 無法分析建構。

## 機器指標 {#machine-metrics}

建構洞察可以包含在建構期間擷取的機器層級效能指標（CPU、記憶體、網路和磁碟使用量）。若要啟用此功能，請設定一個輕量級的後台常駐程式，持續採樣系統指標：

```bash
tuist setup insights
```

這會執行一個在背景採樣指標的本機常駐程式。資料會由 `tuist inspect build` 自動擷取並隨建構報告上傳。

> [!TIP]
> **Ci**
>
> 在建構前於您的 CI 機器上執行 `tuist setup insights`，以同時擷取那裡的機器指標。

若要停止收集機器指標，請執行：

```bash
tuist teardown insights
```

這會卸載常駐程式的 LaunchAgent、移除其 plist，並從 `~/.local/state` 刪除採樣的指標和常駐程式記錄，因此背景中不會有任何程序繼續執行。


## 自訂中繼資料 {#custom-metadata}

您可以使用環境變數將中繼資料附加至建構，以改善篩選功能。

### 環境變數

| 變數 | 格式 | 說明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 單一變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值組，其中後綴為鍵。 |

### 範例

在叫用建構之前，請在 CI 或您的 Shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
