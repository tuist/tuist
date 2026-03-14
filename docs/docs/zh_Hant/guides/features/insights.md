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

處理大型專案不該讓人覺得像是在做苦差事。事實上，它應該像兩週前剛開始的專案一樣令人樂在其中。
之所以並非如此，部分原因在於隨著專案規模擴大，開發者體驗會隨之惡化。建置時間變長，測試變得緩慢且不穩定。這些問題往往容易被忽略，直到情況惡化到難以忍受的地步——然而，到了那個時候，要解決這些問題就變得困難重重。Tuist
Insights 提供您監控專案健康狀況的工具，並在專案擴展時維持高效的開發環境。

換句話說，Tuist Insights 能協助您解答諸如以下的問題：
- 過去一週內，建置時間是否有顯著增加？
- 與本地開發相比，我的 CI 建置速度是否較慢？

雖然您可能已針對 CI
工作流程的效能建立了一些指標，但對於本地開發環境的狀況，您可能無法獲得同等程度的掌握。然而，本地建置時間是影響開發者體驗最重要的因素之一。

若要開始追蹤本地建置時間，您可以將`tuist inspect build` 指令加入方案的後處理動作中：

![檢查建置的後續操作](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
我們建議將「從以下位置提供建置設定」設定為可執行檔或您的主要建置目標，以便 Tuist 能追蹤建置配置。
<!-- -->
:::

::: info
<!-- -->
若未使用
<LocalizedLink href="/guides/features/projects">生成專案</LocalizedLink>，當建置失敗時，後處理程序將不會執行。
<!-- -->
:::
> 
> ` `Xcode 有一項未記載的功能，即使在此情況下也能執行該指令。請在相關專案的 project.pbxproj`
> 檔案中，於方案的`BuildAction` 設定屬性`runPostActionsOnFailure` 為 YES` ，如下所示：
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


只要您登入 Tuist 帳戶，您的本地建置記錄便會被追蹤。現在您可以在 Tuist 儀表板中查看建置時間，並觀察其隨時間的變化：


::: tip
<!-- -->
若要快速存取儀表板，請在命令列介面 (CLI) 中執行`tuist project show --web` 。
<!-- -->
:::

![包含建置分析的儀表板](/images/guides/features/insights/builds-dashboard.png)

## 產生的專案{#generated-projects}

::: info
<!-- -->
自動生成的方案會自動包含`tuist inspect build` 後處理動作。
<!-- -->
:::
> 
> 若您不希望在自動生成的方案中追蹤洞察資訊，請使用
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> 生成選項將其停用。

若您使用的是採用自訂建置方案的生成專案，可為建置分析設定後處理動作：

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

若要在 CI 上追蹤建置分析資料，您必須確保您的 CI 已
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">完成驗證</LocalizedLink>。

此外，您還需執行以下任一操作：
- 執行`xcodebuild` 操作時，請使用
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> 指令。
- `在您的 ``` 中加入 `xcodebuild` ` 指令，並添加參數 `-resultBundlePath` `。

當執行`xcodebuild` 並未指定`-resultBundlePath` 來建置專案時，系統將不會產生所需的活動日誌與結果封裝檔。`tuist
inspect build` 的後續動作需要這些檔案才能分析您的建置結果。
