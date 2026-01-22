---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# 測試洞察{#test-insights}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

測試洞察功能可協助您監控測試套件的健康狀態，透過識別緩慢的測試或快速理解失敗的持續整合執行結果。隨著測試套件規模擴大，要發現測試逐漸變慢或間歇性失敗等趨勢將愈發困難。Tuist
測試洞察提供您所需的可視性，以維持快速且可靠的測試套件。

透過測試洞察，您可解答諸如以下問題：
- 我的測試是否變慢了？哪些測試？
- 哪些測試結果不穩定且需要關注？
- 為何我的 CI 執行失敗？

## 設定{#setup}

要開始追蹤測試，可將以下指令加入方案的測試後處理動作：`tuist inspect test`

![檢查測試後的後續操作](/images/guides/features/insights/inspect-test-scheme-post-action.png)

若您使用的是 [Mise](https://mise.jdx.dev/)，您的腳本需在後處理環境中啟用`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
您的環境變數 ``` PATH `` ` 不會被 scheme post action 繼承，因此必須使用 Mise
的絕對路徑（取決於您的安裝方式）。此外，請記得從專案目標繼承建置設定，以便能從 $SRCROOT 所指向的目錄執行 Mise。
<!-- -->
:::

只要您登入 Tuist 帳戶，所有測試執行紀錄皆會自動追蹤。您可於 Tuist 儀表板查看測試洞察報告，並觀察其隨時間演變的趨勢：

![測試洞察儀表板](/images/guides/features/insights/tests-dashboard.png)

除了整體趨勢外，您亦可深入檢視每個個別測試項目，例如在CI環境中除錯失敗或緩慢的測試時：

![測試詳情](/images/guides/features/insights/test-detail.png)

## 產生的專案{#generated-projects}

::: info
<!-- -->
自動生成方案會自動包含以下後置操作：`tuist inspect test`
<!-- -->
:::
> 
> 若您無意在自動生成方案中追蹤測試洞察，請使用
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>
> 生成選項停用此功能。

若您使用自訂方案的生成專案，可為測試洞察設定後續動作：

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

若未使用 Mise，您的腳本可簡化為：

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

## 持續整合{#continuous-integration}

若要追蹤 CI 上的測試洞察，您需確保您的 CI 已完成
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">驗證</LocalizedLink>。

此外，您還需執行以下任一操作：
- 執行`xcodebuild` 操作時，請使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 指令。
- `在您的 ``` 中加入 `xcodebuild` ` 指令，並添加參數 `-resultBundlePath` `。

當執行 ``` 並使用 `xcodebuild` ` 測試專案時，若未指定 ``` 及
`-resultBundlePath``，所需的結果封裝檔將不會生成。`` 的 `tuist inspect test` `
後置操作需依賴這些檔案來分析測試結果。
