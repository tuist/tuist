---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# 建構洞察{#build-insights}

::: warning REQUIREMENTS
<!-- -->
- A<LocalizedLink href="/guides/server/accounts-and-projects">Tuist帳號與專案</LocalizedLink>
<!-- -->
:::

處理大型專案不該像完成苦差事。事實上，它應該像處理兩週前才啟動的專案般令人愉悅。
之所以未能如此，部分原因在於專案規模擴大時，開發者體驗往往隨之惡化。建置時間延長，測試變得遲緩且不穩定。這些問題通常容易被忽視，直到難以忍受的程度——然而屆時要解決已相當困難。Tuist
Insights 提供監控專案健康狀態的工具，助您在專案擴展時維持高效的開發者環境。

換言之，Tuist Insights 協助您解答諸如：
- 過去一週的建置時間是否顯著增加？
- 我的 CI 編譯速度是否比本地開發慢？

儘管您可能已建立持續整合工作流的效能指標，但對本地開發環境的監控程度可能有所不足。然而，本地建置時間正是影響開發者體驗的核心要素之一。

要開始追蹤本地建置時間，可將以下指令加入方案的後置操作中：`tuist inspect build`

![檢查建置後的後續動作](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
建議將「提供建置設定來源」設定為可執行檔或主要建置目標，以便 Tuist 追蹤建置配置。
<!-- -->
:::

::: info
<!-- -->
若未使用
<LocalizedLink href="/guides/features/projects">自動生成專案</LocalizedLink>，當建置失敗時，後置方案動作將不會執行。
<!-- -->
:::
> 
> `` Xcode 的某項未公開功能允許您在此情況下仍可執行。請於相關專案的`project.pbxproj 檔案中，將方案的`BuildAction
> 設定如下：`runPostActionsOnFailure` 設定為`YES`
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

若您使用的是 [Mise](https://mise.jdx.dev/)，您的腳本需在後處理環境中啟用`tuist` ：
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: tip MISE & PROJECT PATHS
<!-- -->
您的環境變數 ``` PATH `` ` 不會被 scheme post action 繼承，因此必須使用 Mise
的絕對路徑（取決於您的安裝方式）。此外，請記得從專案目標繼承建置設定，以便能從 $SRCROOT 所指向的目錄執行 Mise。
<!-- -->
:::


只要您登入 Tuist 帳戶，您的本地建置現已自動追蹤。您現在可於 Tuist 儀表板查看建置時間，並觀察其隨時間演變的趨勢：


::: tip
<!-- -->
欲快速存取儀表板，請於命令列介面執行：`tuist project show --web`
<!-- -->
:::

![建置洞察儀表板](/images/guides/features/insights/builds-dashboard.png)

## 產生的專案{#generated-projects}

::: info
<!-- -->
自動生成方案會自動包含`tuist inspect build` 後續操作。
<!-- -->
:::
> 
> 若您無意追蹤自動生成架構中的洞察資訊，請使用
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> 生成選項停用此功能。

若您使用自訂方案的生成專案，可為建置洞察設定後置動作：

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
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

若未使用 Mise，您的腳本可簡化為：

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

## 持續整合{#continuous-integration}

若要在持續整合環境中追蹤建置洞察，您需確保您的持續整合系統已完成<LocalizedLink href="/guides/integrations/continuous-integration#authentication">驗證</LocalizedLink>。

此外，您還需執行以下任一操作：
- 執行`xcodebuild` 操作時，請使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 指令。
- `在您的 ``` 中加入 `xcodebuild` ` 指令，並添加參數 `-resultBundlePath` `。

當執行 ``` 並使用 `xcodebuild` ` 編譯專案時，若未指定 ``` 及
`-resultBundlePath``，所需的活動日誌與結果封裝檔將不會產生。而 ``` 中的 `tuist inspect build` `
後置操作需依賴這些檔案來分析建置結果。
