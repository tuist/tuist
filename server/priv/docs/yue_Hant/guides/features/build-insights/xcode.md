---
{
  "title": "Xcode 建構分析",
  "titleTemplate": ":title · 建構分析 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Xcode 建構分析，以監控本地及 CI 建構效能。"
}
---
# Xcode 建置洞察 {#xcode-build-insights}

處理大型專案時，唔應該要重複編譯同一啲代碼。Tuist Build Insights 讓你可以追蹤建置分析數據，喺本地同 CI 建置時間變成瓶頸之前識別趨勢。

建置洞察由 `tuist inspect build` 指令驅動，通常會加到你 scheme 嘅 post-action 入面。

要開始追蹤本地建置時間，你可以將 `tuist inspect build` 指令加到你 scheme 嘅 post-action 入面：

![檢查建置嘅 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設定為可執行檔或你嘅主要建置目標，以捕捉建置設定。


> [!NOTE]
> 當建置失敗時，post-scheme action 唔會執行。

>
> 喺呢種情況下，你可以透過將 `runPostActionsOnFailure` 設定為 `YES` 嚟執行佢，位置係相關嘅 `project.pbxproj` `BuildAction`：
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
> 你環境嘅 `PATH` 唔會被 scheme post action 繼承，所以要用 Mise 嘅絕對路徑。這取決於你點樣安裝 Mise。建置設定應該從目標繼承，咁 `mise` 就可以從 `$SRCROOT` 運行。

對於 [Homebrew](https://brew.sh/)，將 Homebrew 路徑加到 post-action 環境：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claims 預設係禁用嘅。要為 scheme post-action 設定一個，請喺該腳本中設定 `TUIST_ACTOR_ID`，而唔好依賴 shell exports。從 Dock 啟動嘅 Xcode 唔會繼承 `~/.zshrc` 中嘅變數。要明確停用用 Homebrew 設定嘅 claim，請使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 時，喺 Mise 載入其環境後覆蓋該值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用明確標籤代替空值來選擇加入。

登入後，本地建置會被追蹤並可從 Tuist dashboard 查看：

> [!TIP]
> 要快速訪問 dashboard，請從 CLI 運行 `tuist project show --web`。


![帶有建置洞察嘅 Dashboard](/images/guides/features/build-insights/builds-dashboard.png)

## CI 中嘅建置洞察 {#continuous-integration}

要喺 CI 上追蹤建置洞察，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過身份驗證</.localized_link>。

對於由 Xcodebuild 驅動嘅 CI，你需要：
- 調用 `xcodebuild` 操作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加到你嘅 `xcodebuild` 指令。

如果冇 `-resultBundlePath`，必要嘅活動日誌同結果 bundle 唔會生成，`tuist inspect build` 就無法分析建置。

## 私有網絡上免憑證報告 {#network-trusted-publishing}

自託管部署可以允許開發人員無需登入即可發布已完成嘅報告。營運者必須喺實例上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link> 中所述重啟它。這適用於每個受支援嘅專案；dashboard 冇呢個設定。喺你 scheme post-action 或終端機使用嘅環境中設定自託管 URL 同專案。當缺少憑證時，CLI 會自動發現實例政策：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

當真正缺少憑證時，活動日誌同 XCResult bundle 會喺本地解析並作為結構化報告發送。唔會提交原始歸檔、附件、覆蓋率/歷史記錄上傳、遠程處理器、分片引用或選擇性執行證據。報告仍然可見，但無法更新已認證嘅測試用例狀態或驅動隔離/失敗自動化。Dashboard 同其他特權指令仍然需要登入。除非實例單獨啟用網絡信任嘅緩存訪問或已配置憑證，否則請保持緩存集成禁用。

現有憑證保持已認證狀態。無效、損壞、空白或被拒絕刷新嘅憑證會安全失敗並保留喺磁盤上，所以後續指令唔會靜默變成未簽名。重新登入或明確登出作為刻意嘅恢復操作。喺升級免憑證客戶端之前，將每個服務器副本升級到支持發現功能嘅版本，並配置最終服務器 URL 而不使用重定向。舊版冇發現功能嘅服務器、禁用嘅實例同發現失敗仍然需要身份驗證。唔需要客戶端選擇加入。獨立設定 `TUIST_ACTOR_ID=""` 以省略已配置嘅 actor claim；已驗證憑證身份不受影響。

## 機器指標 {#machine-metrics}

建置洞察可以包括喺建置期間捕獲嘅機器級性能指標（CPU、記憶體、網絡同磁盤使用量）。要啟用此功能，請設置一個輕量級後台守護程序，持續採樣系統指標：

```bash
tuist setup insights
```

這會運行一個本地守護程序，喺後台採樣指標。數據會由 `tuist inspect build` 自動拾取並隨建置報告一起上傳。

> [!TIP]
> **Ci**
>
> 喺建置之前喺你嘅 CI 機器上運行 `tuist setup insights`，以同樣捕獲那裡嘅機器指標。

要停止收集機器指標，請運行：

```bash
tuist teardown insights
```

這會卸載守護程序嘅 LaunchAgent，刪除其 plist，並從 `~/.local/state` 刪除採樣嘅指標同守護程序日誌，所以後台唔會有任何東西繼續運行。


## 報告 Actor Claim {#report-actor-claim}

只有當你明確將 `TUIST_ACTOR_ID` 設定為組織範圍嘅標籤時，創建報告嘅請求才會包含可選嘅 `x-tuist-actor-id` 標頭，例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`。預設唔會發送任何標籤，Tuist 亦唔會檢測操作系統用戶名。空嘅 `TUIST_ACTOR_ID` 會省略報告嘅標識符，但唔會移除基於憑證嘅已驗證身份。標識符必須係 1–128 字節嘅非空格可打印 ASCII；無效覆蓋會被省略而唔會回退。如果自定義代理拒絕不熟悉嘅標頭，請使用空環境覆蓋來選擇退出。

已驗證嘅個人憑證具有優先權；否則客戶端報告嘅標識符會顯示為 **未驗證**，並且永遠唔會授予權限或自動鏈接到用戶。標識符對任何可以查看專案報告嘅人都可見，包括專案公開時嘅公眾觀眾，並包含喺數據導出中，所以唔好包含秘密。這適用於建置、測試同命令事件報告。舊服務器忽略可選標頭，新服務器接受冇該標頭嘅舊客戶端。冇標識符嘅新共享令牌報告顯示 **未知**，而唔係發布組織；歷史報告保留其先前歸屬。建置同測試列表區分已驗證用戶同未驗證嘅報告標識符。除非自託管實例明確啟用免憑證報告且客戶端發現該政策，否則仍然需要身份驗證。

## 自定義元數據 {#custom-metadata}

你可以透過環境變數將元數據附加到建置，以改善篩選功能。

### 環境變數

| 變數 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 單一變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴為鍵。 |

### 範例

喺調用建置之前，喺 CI 或你嘅 Shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
