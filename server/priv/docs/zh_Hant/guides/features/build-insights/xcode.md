---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode 建置洞察 {#xcode-build-insights}

處理大型專案時，不應需要重複建置相同的程式碼。Tuist Build Insights 可讓您追蹤建置分析數據，以便在本地和 CI 建置時間成為瓶頸之前識別趨勢。

建置洞察由 `tuist inspect build` 指令驅動，通常會將其新增至您 Scheme 的 post-action。

若要開始追蹤本地建置時間，您可以將 `tuist inspect build` 指令新增至 Scheme 的 post-action 來加以運用：

![用於檢查建置的 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設定為可執行檔或您的主要建置目標，以擷取建置組態。


> [!NOTE]
> 當建置失敗時，不會執行 scheme 的 post-action。

>
> 在這種情況下，您可以透過在相關的 `project.pbxproj` `BuildAction` 中將 `runPostActionsOnFailure` 設定為 `YES` 來執行它：
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
> 您環境中的 `PATH` 不會由 scheme post action 繼承，因此請使用 Mise 的絕對路徑。這取決於您安裝 Mise 的方式。建置設定應從目標繼承，以便 `mise` 可以從 `$SRCROOT` 執行。

對於 [Homebrew](https://brew.sh/)，請將 Homebrew 路徑新增至 post-action 環境：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claims 預設為停用。若要為 scheme post-action 進行組態，請在該腳本中設定 `TUIST_ACTOR_ID`，而不是依賴 shell exports。從 Dock 啟動的 Xcode 不會繼承來自 `~/.zshrc` 的變數。若要明確抑制使用 Homebrew 設定的 claim，請使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 時，請在 Mise 載入其環境後覆寫該值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用明確的標籤而非空值來選擇加入。

登入後，系統會追蹤本地建置，並可從 Tuist 儀表板存取：

> [!TIP]
> 若要快速存取儀表板，請從 CLI 執行 `tuist project show --web`。


![包含建置洞察的儀表板](/images/guides/features/build-insights/builds-dashboard.png)

## CI 中的建置洞察 {#continuous-integration}

若要在 CI 上追蹤建置洞察，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，您需要：
- 在叫用 `xcodebuild` 動作時，使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 新增至您的 `xcodebuild` 指令。

若沒有 `-resultBundlePath`，則不會產生必要的活動日誌和結果套件，且 `tuist inspect build` 無法分析建置。

## 私人網路上的免憑證報告 {#network-trusted-publishing}

自行託管的部署可讓開發人員無需登入即可發布完成的報告。營運者必須在實例上組態 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true`，並按照<.localized_link href="/guides/server/self-host/server#network-trusted-access">自行託管指南</.localized_link>所述重新啟動。這適用於每個受支援的專案；儀表板中沒有相關設定。請在您的 scheme post-action 或終端機所使用的環境中，組態自行託管的 URL 和專案。當缺少憑證時，CLI 會自動探索實例政策：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

在真正缺少憑證的情況下，活動日誌和 XCResult 套件會在本地解析並作為結構化報告傳送。不會提交原始封存、附件、涵蓋率/歷史記錄上傳、遠端處理器、分片參考或選擇性執行證據。報告仍然可見，但無法更新經過驗證的測試案例狀態或驅動隔離/失敗自動化。儀表板和其他特權指令仍然需要登入。除非實例另行啟用網路信任的快取存取或已佈建憑證，否則請保持快取整合停用。

現有的憑證仍保持通過驗證狀態。無效、損毀、空白或被拒絕重新整理的憑證會以失敗關閉並保留在磁碟上，因此後續指令不會在未經簽署的情況下靜默執行。請重新登入或明確登出，作為 deliberate recovery action。在升級免憑證用戶端之前，請將每個伺服器副本升級至支援探索功能的版本，並在不使用重新導向的情況下組態最終伺服器 URL。不具備探索功能的舊版伺服器、已停用的實例以及探索失敗的情況仍然需要驗證。不需要用戶端選擇加入。獨立設定 `TUIST_ACTOR_ID=""` 以省略已組態的 actor claim；已驗證的憑證身分不受影響。

## 機器指標 {#machine-metrics}

建置洞察可以包含在建置期間擷取的機器層級效能指標（CPU、記憶體、網路和磁碟使用量）。若要啟用此功能，請設定一個輕量級的背景常駐程式，持續採樣系統指標：

```bash
tuist setup insights
```

這會執行一個在背景採樣指標的本地常駐程式。資料會由 `tuist inspect build` 自動擷取，並與建置報告一起上傳。

> [!TIP]
> **CI**
>
> 在建置之前，請在您的 CI 機器上執行 `tuist setup insights`，以便同時在那裡擷取機器指標。

若要停止收集機器指標，請執行：

```bash
tuist teardown insights
```

這會卸載常駐程式的 LaunchAgent、移除其 plist，並從 `~/.local/state` 刪除採樣的指標和常駐程式日誌，因此背景中不會有任何程序仍在執行。


## 報告 Actor Claim {#report-actor-claim}

只有在您將 `TUIST_ACTOR_ID` 明確設定為組織範圍的標籤（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`）時，建立報告的請求才會包含可選的 `x-tuist-actor-id` 標頭。預設不會傳送任何標籤，且 Tuist 不會偵測作業系統使用者名稱。空的 `TUIST_ACTOR_ID` 會省略報告的識別碼，但不會移除基於憑證的已驗證身分。識別碼必須是 1–128 位元組的非空格可列印 ASCII；無效的覆寫會被省略，且不會回退。如果自訂 Proxy 拒絕不熟悉的標頭，請使用空的環境覆寫來選擇退出。

已驗證的個人憑證具有優先權；否則，用戶端報告的識別碼會顯示為**未經驗證**，且永遠不會授予權限或自動連結至使用者。任何可以檢視專案報告的人都能看到識別碼，包括專案公開時的公眾檢視者，並且識別碼會包含在資料匯出中，因此請勿包含機密資訊。這適用於建置、測試和指令事件報告。舊版伺服器會忽略可選標頭，而新版伺服器會接受沒有該標頭的舊版用戶端。沒有識別碼的新共用令牌報告會顯示**未知**，而非發布組織；歷史報告會保留其先前的歸屬。建置和測試清單會區分已驗證的使用者和未經驗證的報告識別碼。除非自行託管的實例明確啟用免憑證報告且用戶端探索到該政策，否則仍然需要驗證。

## 自訂中繼資料 {#custom-metadata}

您可以透過環境變數將中繼資料附加到建置，以改善篩選功能。

### 環境變數

| 變數 | 格式 | 說明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 在一個變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴為鍵。 |

### 範例

在叫用您的建置之前，請在 CI 或您的 Shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
