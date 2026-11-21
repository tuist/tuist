---
{
  "title": "Xcode 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Xcode 構建分析數據，以監察本地及 CI 構建效能。"
}
---
# Xcode 建構分析 {#xcode-build-insights}

處理大型專案時，唔應該要重複建構相同嘅代碼。Tuist Build Insights 讓你可以追蹤建構數據分析，喺本地同 CI 建構時間成為瓶頸之前識別趨勢。

建構分析由 `tuist inspect build` 指令驅動，通常會加到你 scheme 嘅 post-action 入面。

要開始追蹤本地建構時間，你可以透過將 `tuist inspect build` 指令加到你 scheme 嘅 post-action 嚟利用佢：

![檢查建構嘅 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設定為可執行檔或你嘅主要建構目標，以捕捉建構設定。

> [!NOTE]
> 當建構失敗時，post-scheme action 唔會執行。
>
> 喺呢種情況下，你可以透過將 scheme 嘅 `.xcscheme` 檔案中 `<BuildAction>` 元素上嘅 `runPostActionsOnFailure` 設定為 `YES` 嚟執行佢：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

對於 [Mise](https://mise.jdx.dev/)，喺 post-action 環境中啟用 `tuist`：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 路徑解析**
>
> 你環境嘅 `PATH` 唔會被 scheme post action 繼承，所以要用 Mise 嘅絕對路徑。這取決於你點樣安裝 Mise。建構設定應該從目標繼承，令到 `mise` 可以從 `$SRCROOT` 運行。

對於 [Homebrew](https://brew.sh/)，將 Homebrew 路徑加到 post-action 環境：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

登入後，本地建構會被追蹤並可從 Tuist 儀表板查看：

> [!TIP]
> 要快速訪問儀表板，請從 CLI 運行 `tuist project show --web`。

![帶有建構分析嘅儀表板](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
