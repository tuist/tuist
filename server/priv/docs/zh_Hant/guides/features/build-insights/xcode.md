---
{
  "title": "Xcode 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Xcode 建置分析，以監控本機與 CI 建置效能。"
}
---
# Xcode 建置洞察 {#xcode-build-insights}

開發大型專案時，不應反覆重新建置相同的程式碼。Tuist Build Insights 可讓你追蹤建置分析數據，以便在本機與 CI 建置時間成為瓶頸之前識別趨勢。

建置洞察由 `tuist inspect build` 指令驅動，通常會加入至你的 Scheme 後置動作中。

若要開始追蹤本機建置時間，你可以將 `tuist inspect build` 指令加入至你的 Scheme 後置動作來使用：

![用於檢查建置的後置動作](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設定為可執行檔或你的主要建置目標，以擷取建置設定。

> [!NOTE]
> 當建置失敗時，不會執行 Scheme 後置動作。
>
> 在此情況下，你可以將方案 `.xcscheme` 檔案中 `<BuildAction>` 元素的 `runPostActionsOnFailure` 設為 `YES` 來執行：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

對於 [Mise](https://mise.jdx.dev/)，請在後置動作環境中啟用 `tuist`：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 路徑解析**
>
> 你的環境變數 `PATH` 不會被 Scheme 後置動作繼承，因此請使用 Mise 的絕對路徑。這取決於你安裝 Mise 的方式。建置設定應從目標繼承，如此 `mise` 才能從 `$SRCROOT` 執行。

對於 [Homebrew](https://brew.sh/)，請將 Homebrew 路徑加入至後置動作環境：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

登入後，系統會追蹤本機建置，並可在 Tuist 儀表板中查看：

> [!TIP]
> 若要快速存取儀表板，請從 CLI 執行 `tuist project show --web`。

![包含建置洞察的儀表板](/images/guides/features/build-insights/builds-dashboard.png)

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
