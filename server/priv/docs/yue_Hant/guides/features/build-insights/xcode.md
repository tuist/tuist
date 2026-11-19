---
{
  "title": "Xcode 建置分析",
  "titleTemplate": ":title · 建置分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Xcode 建置分析數據，監察本地及 CI 建置效能。"
}
---
# Xcode 編譯分析 {#xcode-build-insights}

處理大型專案時，不應重複編譯相同代碼。Tuist Build Insights 讓你追蹤編譯數據，以便在本地和 CI 編譯時間成為瓶頸之前識別趨勢。

編譯分析由 `tuist inspect build` 指令驅動，通常會加入到你 scheme 的 post-action 中。

要開始追蹤本地編譯時間，你可以將 `tuist inspect build` 指令加入到 scheme 的 post-action 中：

![檢查編譯的 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設定為可執行檔或你的主要編譯目標，以擷取編譯配置。

> [!NOTE]
> 當編譯失敗時，不會執行 post-scheme action。
>
> 在這種情況下，你可以透過在 scheme 的 `.xcscheme` 檔案中，將 `<BuildAction>` 元素的 `runPostActionsOnFailure` 設定為 `YES` 來執行它：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

對於 [Mise](https://mise.jdx.dev/)，請在 post-action 環境中啟用 `tuist`：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 路徑解析**
>
> 你環境中的 `PATH` 不會被 scheme post action 繼承，因此請使用 Mise 的絕對路徑。這取決於你如何安裝 Mise。編譯設定應從目標繼承，以便 `mise` 可以從 `$SRCROOT` 執行。

對於 [Homebrew](https://brew.sh/)，請將 Homebrew 路徑加入到 post-action 環境中：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

登入後，本地編譯會被追蹤並可在 Tuist 儀表板中查看：

> [!TIP]
> 若要快速存取儀表板，請從 CLI 執行 `tuist project show --web`。

![包含編譯分析的儀表板](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
