---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode 構建洞察 {#xcode-build-insights}

處理大型項目時，不應需要重複構建相同的代碼。Tuist Build Insights 讓你可以追蹤構建分析數據，以便在本地和 CI 構建時間成為瓶頸之前識別趨勢。

構建洞察由 `tuist inspect build` 命令驅動，該命令通常添加到你的 scheme 的 post-action 中。

要開始追蹤本地構建時間，你可以將 `tuist inspect build` 命令添加到你的 scheme 的 post-action 中來利用它：

![檢查構建的 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設置為可執行文件或你的主要構建目標，以捕獲構建配置。


> [!NOTE]
> 當構建失敗時，不會執行 post-scheme action。

>
> 在這種情況下，你可以通過在相關的 `project.pbxproj` `BuildAction` 中將 `runPostActionsOnFailure` 設置為 `YES` 來執行它：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

對於 [Mise](https://mise.jdx.dev/)，在 post-action 環境中激活 `tuist`：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 路徑解析**
>
> 你環境中的 `PATH` 不會被 scheme post action 繼承，因此請使用 Mise 的絕對路徑。這取決於你如何安裝 Mise。構建設置應從目標繼承，以便 `mise` 可以從 `$SRCROOT` 運行。

對於 [Homebrew](https://brew.sh/)，將 Homebrew 路徑添加到 post-action 環境中：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claims 默認情況下是禁用的。要為 scheme post-action 配置一個，請在該腳本中設置 `TUIST_ACTOR_ID`，而不是依賴 shell exports。從 Dock 啟動的 Xcode 不會繼承 `~/.zshrc` 中的變量。要使用 Homebrew 明確抑制配置的 claim，請使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 時，在 Mise 加載其環境後覆蓋該值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用明確的標籤而不是空值來選擇加入。

登錄後，本地構建會被追蹤並可從 Tuist 儀表板查看：

> [!TIP]
> 要快速訪問儀表板，請從 CLI 運行 `tuist project show --web`。


![帶有構建洞察的儀表板](/images/guides/features/build-insights/builds-dashboard.png)

## CI 中的構建洞察 {#continuous-integration}

要在 CI 上追蹤構建洞察，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，你需要：
- 在調用 `xcodebuild` 操作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 添加到你的 `xcodebuild` 命令中。

如果沒有 `-resultBundlePath`，則不會生成所需的活動日誌和結果包，且 `tuist inspect build` 無法分析構建。

## 私有網絡上的無憑證報告 {#network-trusted-publishing}

自託管部署可以允許開發人員在不登錄的情況下發布完成的報告。操作員必須在實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link> 中的描述重新啟動它。這適用於每個受支持的項目；沒有儀表板設置。在你的 scheme post-action 或終端使用的環境中配置自託管 URL 和項目。當缺少憑證時，CLI 會自動發現實例策略：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

在真正缺少憑證的情況下，活動日誌和 XCResult 包會在本地解析並作為結構化報告發送。不會提交原始歸檔、附件、覆蓋率/歷史記錄上傳、遠程處理器、分片引用或選擇性執行證據。報告仍然可見，但無法更新經過驗證的測試用例狀態或驅動隔離/失敗自動化。儀表板和其他特權命令仍然需要登錄。除非實例單獨啟用了網絡信任的緩存訪問或提供了憑證，否則請保持緩存集成禁用。

現有憑證保持驗證狀態。無效、損壞、空白或被拒絕刷新的憑證會失敗並保留在磁盤上，因此後續命令不會靜默變為未簽名。再次登錄或明確登出作為 deliberate recovery action。在升級無憑證客戶端之前，將每個服務器副本升級到支持發現的版本，並配置最終服務器 URL 而不進行重定向。較舊的不支持發現的服務器、禁用的實例和發現失敗仍然需要驗證。不需要客戶端選擇加入。獨立設置 `TUIST_ACTOR_ID=""` 以省略配置的 actor claim；經過驗證的憑證身份不受影響。

## 機器指標 {#machine-metrics}

構建洞察可以包括在構建期間捕獲的機器級性能指標（CPU、內存、網絡和磁盤使用情況）。要啟用此功能，請設置一個輕量級的後台守護進程，持續採樣系統指標：

```bash
tuist setup insights
```

這會運行一個在後台採樣指標的本地守護進程。數據會由 `tuist inspect build` 自動拾取並與構建報告一起上傳。

> [!TIP]
> **Ci**
>
> 在構建之前在您的 CI 機器上運行 `tuist setup insights`，以在那裡也捕獲機器指標。

要停止收集機器指標，請運行：

```bash
tuist teardown insights
```

這會卸載守護進程的 LaunchAgent，刪除其 plist，並從 `~/.local/state` 中刪除採樣的指標和守護進程日誌，因此後台不會有任何東西在運行。


## 報告 actor claim {#report-actor-claim}

僅當你將 `TUIST_ACTOR_ID` 明確設置為組織範圍的標籤（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`）時，創建報告的請求才會包含可選的 `x-tuist-actor-id` 標頭。默認情況下不會發送標籤，且 Tuist 不會檢測操作系統用戶名。空的 `TUIST_ACTOR_ID` 會省略報告的標識符，但不會刪除基於憑證的驗證身份。標識符必須是 1–128 字節的非空格可打印 ASCII；無效的覆蓋會被省略而不會回退。如果自定義代理拒絕不熟悉的標頭，請使用空環境覆蓋來選擇退出。

經過驗證的個人憑證具有優先權；否則，客戶端報告的標識符顯示為 **未驗證**，並且從不授予權限或自動鏈接到用戶。任何可以查看項目報告的人都可以看到標識符，包括項目公開時的公共觀眾，並且包含在數據導出中，因此不要包含機密信息。這適用於構建、測試和命令事件報告。舊服務器忽略可選標頭，新服務器接受沒有它的舊客戶端。沒有標識符的新共享令牌報告顯示 **未知**，而不是發布組織；歷史報告保留其先前的歸因。構建和測試列表區分經過驗證的用戶和未驗證的報告標識符。除非自託管實例明確啟用無憑證報告且客戶端發現該策略，否則仍然需要驗證。

## 自定義元數據 {#custom-metadata}

你可以透過環境變數將元數據附加到構建中，以改善篩選功能。

### 環境變數

| 變數 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 一個變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴為鍵。 |

### 範例

在調用構建之前，在 CI 或你的 shell 中設置這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
