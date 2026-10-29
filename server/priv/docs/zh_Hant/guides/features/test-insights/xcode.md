---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Xcode 測試洞察 {#xcode-test-insights}

Tuist Test Insights 提供 Xcode 測試分析功能，讓您透過識別緩慢的測試或快速了解失敗的 CI 執行來監控測試套件的健全性。隨著您的測試套件增長，越來越難以發現逐漸變慢的測試或間歇性失敗等趨勢。Tuist Test Insights 提供您維持快速且可靠測試套件所需的可見度。

使用 Test Insights，您可以回答以下問題：
- 我的測試是否變慢了？哪些測試？
- 哪些測試不穩定且需要關注？
- 為什麼我的 CI 執行失敗了？

## 設定 {#setup}

要開始追蹤您的測試，您可以利用 `tuist inspect test` 指令，將其加入至方案的測試後動作中：

![檢查測試的後動作](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

如果您使用的是 [Mise](https://mise.jdx.dev/)，您的腳本需要在後動作環境中啟用 `tuist`：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise 與專案路徑**
>
> 您環境中的 `PATH` 環境變數不會被方案後動作繼承，因此您必須使用 Mise 的絕對路徑，這取決於您如何安裝 Mise。此外，別忘了從專案中的目標繼承建置設定，這樣您才能從 $SRCROOT 指向的目錄執行 Mise。

只要您登入 Tuist 帳號，系統就會追蹤您的測試執行。您可以在 Tuist 儀表板中存取測試洞察，並查看其隨時間的變化：

![包含測試洞察的儀表板](/images/guides/features/build-insights/tests-dashboard.png)

除了整體趨勢外，您也可以深入檢視每個單獨的測試，例如在 CI 上偵錯失敗或緩慢的測試時：

![測試詳細資訊](/images/guides/features/build-insights/test-detail.png)

## 產生的專案 {#generated-projects}

> [!NOTE]
> 自動產生的方案會自動包含 `tuist inspect test` 後動作。

>
> 如果您不想在自動產生的方案中追蹤測試洞察，請使用 [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 產生選項來停用它們。

如果您使用帶有自訂方案的產生專案，可以為測試洞察設定後動作：

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

如果您沒有使用 Mise，您的腳本可以簡化為：

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

要在 CI 上追蹤測試洞察，您需要確保您的 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過驗證</.localized_link>。

此外，您需要：
- 在叫用 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> 指令。
- 將 `-resultBundlePath` 加入至您的 `xcodebuild` 叫用中。

當 `xcodebuild` 測試您的專案而未使用 `-resultBundlePath` 時，不會產生必要的結果套件檔案。`tuist inspect test` 後動作需要這些檔案來分析您的測試。

### Git 歷史記錄 {#git-history}

在 CI 上，Tuist 也會上傳檢出的提交歷史記錄：提交 SHA、其父節點、提交日期，以及執行和其拉取請求基底分支所在的分支。不會上傳任何檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併至您的預設分支，例如合併佇列測試過的提交。Tuist 會讀取检出已有的歷史記錄，當检出沒有基底分支時，會向遠端查詢其最新提交 (`git ls-remote`)。除程式碼涵蓋率外，它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取检出，而不聯絡遠端。 |
