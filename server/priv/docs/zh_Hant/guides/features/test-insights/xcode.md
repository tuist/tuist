---
{
  "title": "Xcode 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試洞察追蹤 Xcode 測試分析數據，找出緩慢與不穩定測試。"
}
---
# Xcode 測試洞察 {#xcode-test-insights}

Tuist Test Insights 提供 Xcode 測試分析，協助你監控測試套件的健全狀況，找出執行緩慢的測試，或快速了解 CI 執行失敗的原因。隨著測試套件規模擴大，要察覺如測試逐漸變慢或間歇性失敗等趨勢會愈來愈困難。Tuist Test Insights 提供必要的可見度，讓你維持快速且可靠的測試套件。

透過 Test Insights，你可以回答以下問題：
- 我的測試是否變慢了？是哪些測試？
- 哪些測試不穩定且需要關注？
- 為什麼我的 CI 執行失敗？

## 設定 {#setup}

若要開始追蹤測試，你可以將 `tuist inspect test` 指令加入方案的測試後動作（post-action）：

![用於檢查測試的後動作](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

若你使用 [Mise](https://mise.jdx.dev/)，你的腳本需要在後動作環境中啟用 `tuist`：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise 與專案路徑**
>
> 你的環境中的 `PATH` 環境變數不會被方案的後動作繼承，因此你必須使用 Mise 的絕對路徑，具體取決於你安裝 Mise 的方式。此外，別忘了從專案中的某個目標繼承建置設定，這樣你才能從 $SRCROOT 指向的目錄執行 Mise。

只要你已登入 Tuist 帳號，系統就會追蹤你的測試執行。你可以在 Tuist 儀表板中查看測試洞察，並觀察其隨時間的變化：

![包含測試洞察的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

除了整體趨勢外，你也可以深入檢視每個單獨的測試，例如在 CI 上除錯失敗或緩慢的測試時：

![測試詳細資訊](/images/guides/features/build-insights/test-detail.png)

## 產生的專案 {#generated-projects}

> [!NOTE]
> 自動產生的方案會自動包含 `tuist inspect test` 後動作。

>
> 若你不希望在自動產生的方案中追蹤測試洞察，請使用 [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 產生選項來停用。

若你使用帶有自訂方案的產生專案，可以為測試洞察設定後動作：

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

若你未使用 Mise，你的腳本可以簡化為：

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

## 持續整合 {#continuous-integration}

若要在 CI 上追蹤測試洞察，您必須確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">驗證</.localized_link>。

此外，你需要：
- 在叫用 `xcodebuild` 動作時，使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> 指令。
- 在你的 `xcodebuild` 叫用中加入 `-resultBundlePath`。

當 `xcodebuild` 測試你的專案但未提供 `-resultBundlePath` 時，不會產生所需的結果套件檔案。`tuist inspect test` 後動作需要這些檔案來分析你的測試。

### Git 歷史記錄 {#git-history}

在 CI 上，Tuist 也會上傳 checkout 的提交歷史記錄：提交 SHA、其父提交、提交日期，以及該次執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併到你的預設分支，例如合併佇列所測試的提交。Tuist 會讀取 checkout 中已有的歷史記錄；若 checkout 沒有基礎分支，則會向遠端查詢最新的提交（`git ls-remote`）。除程式碼涵蓋率外，它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取 checkout，不會聯絡遠端。 |
