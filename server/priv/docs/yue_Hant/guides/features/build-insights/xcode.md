---
{
  "title": "Xcode Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Xcode build analytics in the Tuist dashboard to monitor local and CI build performance."
}
---
# Xcode 建置深入分析 {#xcode-build-insights}

處理大型專案時，不應需要重複建置相同的程式碼。Tuist Build Insights 讓你追蹤建置分析數據，以便在本地和 CI 建置時間成為瓶頸之前識別趨勢。

建置深入分析由 `tuist inspect build` 指令驅動，通常會將其加入至你 scheme 的 post-action。

要開始追蹤本地建置時間，你可以將 `tuist inspect build` 指令加入至 scheme 的 post-action 來利用它：

![檢查建置的 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 將「Provide build settings from」欄位設定為可執行檔或你的主要建置目標，以擷取建置設定。


> [!NOTE]
> 當建置失敗時，不會執行 post-scheme action。

>
> 在這種情況下，你可以透過在相關的 `project.pbxproj` `BuildAction` 中將 `runPostActionsOnFailure` 設定為 `YES` 來執行它：
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
> 你環境中的 `PATH` 不會被 scheme post action 繼承，因此請使用 Mise 的絕對路徑。這取決於你如何安裝 Mise。建置設定應從目標繼承，以便 `mise` 可以從 `$SRCROOT` 執行。

對於 [Homebrew](https://brew.sh/)，請將 Homebrew 路徑加入至 post-action 環境：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claims 預設為停用。若要為 scheme post-action 設定一個，請在該腳本中設定 `TUIST_ACTOR_ID`，而不是依賴 shell exports。從 Dock 啟動的 Xcode 不會繼承來自 `~/.zshrc` 的變數。若要明確地使用 Homebrew 抑制已設定的 claim，請使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 時，在 Mise 載入其環境後覆寫值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用明確的標籤而非空值來選擇加入。

登入後，本地建置會被追蹤並可從 Tuist dashboard 取得：

> [!TIP]
> 若要快速存取 dashboard，請從 CLI 執行 `tuist project show --web`。


![包含建置深入分析的 Dashboard](/images/guides/features/build-insights/builds-dashboard.png)

## CI 中的建置深入分析 {#continuous-integration}

若要在 CI 上追蹤建置深入分析，請確保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">通過驗證</.localized_link>。

對於由 Xcodebuild 驅動的 CI，你需要：
- 在叫用 `xcodebuild` 動作時使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 將 `-resultBundlePath` 加入至你的 `xcodebuild` 指令。

如果沒有 `-resultBundlePath`，則不會產生所需的活動日誌和結果套件，且 `tuist inspect build` 無法分析建置。

## 在私人網路上進行免憑證報告 {#network-trusted-publishing}

自行託管的部署可以讓開發人員無需登入即可發布完成的報告。營運者必須在實例上設定 `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true`，並按照 <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">自行託管指南</.localized_link> 所述重新啟動它。這適用於每個支援的專案；dashboard 中沒有相關設定。在你的 scheme post-action 或終端機使用的環境中設定自行託管的 URL 和專案。當缺少憑證時，CLI 會自動探索實例政策：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

當憑證真正缺失時，活動日誌和 XCResult 套件會在本地解析並作為結構化報告發送。不會提交原始封存、附件、涵蓋率/歷史記錄上傳、遠端處理器、分片參考或選擇性執行證據。報告仍然可見，但無法更新已驗證的測試案例狀態或驅動隔離/失敗自動化。Dashboard、快取和其他需要驗證的指令仍然需要登入。如果未提供憑證，請保持任何快取整合停用。

現有的憑證仍保持驗證狀態。無效、損壞、空白或被拒絕刷新的憑證會以安全方式失敗並保留在磁碟上，因此後續指令不會無聲地變成未簽署狀態。請重新登入或明確登出作為刻意恢復動作。在升級免憑證用戶端之前，將每個伺服器副本升級至支援探索功能的版本，並設定最終伺服器 URL 而不使用重新導向。不支援探索功能的舊伺服器、停用的實例以及探索失敗的情況仍然需要驗證。不需要用戶端選擇加入。獨立設定 `TUIST_ACTOR_ID=""` 以省略已設定的 actor claim；已驗證的憑證身分不受影響。

## 機器指標 {#machine-metrics}

建置深入分析可以包含在建置期間擷取的機器層級效能指標（CPU、記憶體、網路和磁碟使用量）。若要啟用此功能，請設定一個輕量級的背景常駐程式，持續採樣系統指標：

```bash
tuist setup insights
```

這會執行一個在背景採樣指標的本地常駐程式。資料會由 `tuist inspect build` 自動擷取並隨建置報告上傳。

> [!TIP]
> **Ci**
>
> 在建置之前，在你的 CI 機器上執行 `tuist setup insights`，以便也在那裡擷取機器指標。

若要停止收集機器指標，請執行：

```bash
tuist teardown insights
```

這會卸載常駐程式的 LaunchAgent、移除其 plist，並從 `~/.local/state` 刪除採樣的指標和常駐程式日誌，因此背景中不會有任何東西繼續執行。


## 報告 actor claim {#report-actor-claim}

只有在將 `TUIST_ACTOR_ID` 明確設定為組織範圍的標籤時（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`），建立報告的請求才會包含可選的 `x-tuist-actor-id` 標頭。預設不會發送標籤，且 Tuist 不會偵測作業系統使用者名稱。空的 `TUIST_ACTOR_ID` 會省略報告的識別碼，但不會移除基於憑證的已驗證身分。識別碼必須是 1–128 位元組的非空格可列印 ASCII；無效的覆寫會被省略且不會回退。如果自訂 proxy 拒絕不熟悉的標頭，請使用空環境覆寫來選擇退出。

已驗證的個人憑證具有優先權；否則，用戶端報告的識別碼會顯示為**未驗證**，且永遠不會授予權限或自動連結至使用者。任何可以檢視專案報告的人都能看到識別碼，包括專案公開時的公眾檢視者，並且會包含在資料匯出中，因此請勿包含機密資訊。這適用於建置、測試和指令事件報告。舊伺服器會忽略可選標頭，而新伺服器會接受沒有該標頭的舊用戶端。沒有識別碼的新共用令牌報告會顯示**未知**，而非發布組織；歷史報告會保留其先前的歸屬。建置和測試清單會區分已驗證的使用者和未驗證的報告識別碼。除非自行託管的實例明確啟用免憑證報告且用戶端發現該政策，否則仍然需要驗證。

## 自訂中繼資料 {#custom-metadata}

你可以使用環境變數將中繼資料附加到建置，以改善篩選功能。

### 環境變數

| 變數 | 格式 | 說明 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗號分隔 | 單一變數中包含多個標籤。 |
| `TUIST_BUILD_VALUE_*` | 單一值 | 鍵值對，其中後綴為鍵。 |

### 範例

在叫用建置之前，請在 CI 或你的 shell 中設定這些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
