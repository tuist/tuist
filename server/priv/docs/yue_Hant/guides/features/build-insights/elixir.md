---
{
  "title": "Elixir Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track how long your Elixir project takes to compile with Mix, its warnings, and the files that hold your builds back."
}
---
# Elixir 建構洞察 {#elixir-build-insights}

Tuist 的 Hex 套件可以將建構分析數據傳送到 Tuist。建構時間、檔案之間的依賴關係圖，以及兩者隨時間的變化，為你提供優化建構圖並充分利用編譯環境中所有核心所需的資訊。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 回報你的建構 {#report-your-builds}

共用設定會安裝編譯整合功能。請繼續使用你慣用的指令：

```bash
mix compile
```

此整合涵蓋 `mix compile` 以及由其他任務觸發的每次編譯，例如 `mix test` 或 `mix phx.server`。如果編譯發現沒有工作需要執行，則不會進行回報，因此儀表板只會列出實際有工作的建構。

## 回報 Actor 聲明 {#report-actor-claim}

只有在明確設定標籤時，Mix 建構和測試回報請求才會包含可選的 `x-tuist-actor-id` 標頭。將 `TUIST_ACTOR_ID` 設定為組織範圍的標籤，或在專案的 `tuist` 設定中加入 `actor_id: "developer-label"`。解析順序優先採用環境變數，其次是執行階段 `:actor_id` 選項，最後是專案設定。預設不會傳送任何標籤，且套件不會偵測作業系統使用者名稱。固定的專案標籤適用於所有使用該設定的使用者。空白或無效的覆寫會省略聲明而非回退；這不會移除基於憑證的已驗證身分。如果自訂 Proxy 拒絕不熟悉的標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

識別碼必須是 1–128 位元組的非空格可列印 ASCII 字元。無效的覆寫會被省略而不會回退。已驗證的個人憑證具有優先權；其他由客戶端回報的識別碼會顯示為 **未驗證**，絕不會授權存取，也絕不會自動連結至使用者。任何能夠檢視專案報告的人都能看到這些識別碼，包括專案公開時的公開檢視者，且它們會包含在資料匯出中，因此請勿包含機密資訊。舊版伺服器會忽略此可選標頭，而新版伺服器會接受沒有此標頭的舊版客戶端。沒有識別碼的新共用權杖報告會顯示 **未知**，而非發布組織；歷史報告會保留其先前的歸因。預設情況下，建構和測試回報需要驗證。自行託管的安裝可以按照下述方式明確啟用免憑證回報。

## 私人網路上的免憑證回報 {#network-trusted-publishing}

當營運者在實例上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自行託管指南</.localized_link> 中的說明重新啟動後，請設定你的目的地。當缺少憑證時，SDK 會自動偵測實例是否允許免憑證回報。此實例設定涵蓋每個支援的專案，且儀表板上沒有切換開關：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` 和 `mix tuist.test` 會在憑證確實不存在且偵測確認伺服器允許的情況下，無需登入即可發布結構化報告。不需要客戶端旗標或專案選擇加入。現有的憑證（包括提供的 CI OIDC 身分）會被使用或拒絕，絕不會被忽略以降級為未簽名回報。僅包含空白的 `TUIST_TOKEN` 會導致錯誤。空的 `TUIST_TOKEN` 可以回退至有效的儲存憑證或提供的 OIDC，而过期的儲存憑證也可以回退至提供的 OIDC；這兩種途徑都保持驗證狀態，絕不會啟用未簽名回報。無法使用的憑證會被保留，並在沒有驗證回退成功時失敗。在升級免憑證客戶端之前，請將每個伺服器副本升級至支援偵測的版本；不支援偵測的舊版伺服器、已停用的實例以及偵測失敗的情況仍然需要驗證。

未簽名的執行屬於遙測數據，並非可信的不穩定性、隔離、涵蓋率或選擇性執行的證據。分片規劃、建構封存以及涵蓋率/成品端點仍然需要憑證。獨立設定 `TUIST_ACTOR_ID=""` 以省略已設定的 actor 聲明；已驗證的憑證身分不受影響。

## 追蹤內容 {#what-is-tracked}

對於每次建構，套件會收集：
- 其持續時間、是否成功，以及執行時的 Elixir、Erlang/OTP 和 Mix 環境
- 每個警告和錯誤，及其所在的檔案和行號
- 每個檔案的編譯時間，以及其定義的模組
- 每個檔案所依賴的檔案，以及是在編譯時還是僅在執行時需要它們
- 除了編譯檔案之外建構執行的操作，例如類型檢查、寫入磁碟以及其他 Mix 編譯器
- 建構期間機器的處理器、記憶體、網路和磁碟使用情況
- 分支和提交，以及在持續整合中的提供者和執行

## 找出拖慢建構速度的原因 {#find-what-slows-a-build-down}

從儀表板的 **建構 → 建構執行** 開啟建構。建構、其診斷計數以及其依賴快取摘要也可透過 `tuist build mix list` 和 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds`，以及 `list_mix_builds` 和 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得。

**概覽** 分頁列出建構編譯的檔案。你可以依模組將它們分組、搜尋它們，並依以下方式排序：
- **編譯持續時間**，以找出本身速度較慢的檔案。
- **編譯時依賴者**，即在此檔案編譯完成前無法編譯的檔案數量。擁有許多依賴者的緩慢檔案會阻礙其餘建構進度，且變更它會重新編譯所有依賴者。
- **編譯時依賴項**，即此檔案等待的檔案數量。

![Phoenix 應用程式的 Mix 建構概覽](/images/guides/features/elixir/build.png)

**時間軸** 分頁顯示同一建構隨時間的變化：哪些檔案平行編譯、建構在何處進行類型檢查和寫入磁碟，以及機器在每個時刻的狀態。只有一條橫條的區段表示建構無法使用其可用的核心。

![Phoenix 應用程式完整 Mix 建構的時間軸](/images/guides/features/elixir/build-timeline.png)

**警告** 和 **錯誤** 分頁列出建構的診斷資訊。

## 自訂中繼資料 {#custom-metadata}

將標籤和鍵值資料附加到 Mix 建構，以區分來自不同團隊、硬體或工作流程的執行。兩者都會出現在每個建構的詳細資訊頁面。

使用環境變數設定中繼資料：

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

你也可以在 `mix.exs` 中設定中繼資料：

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

兩處的標籤會合併。當兩處設定了相同的鍵時，環境變數中的值優先。

標籤只能包含字母、數字、連字號和底線。一個建構最多可以有 50 個標籤，每個標籤最多可以包含 50 個字元。一個建構最多可以有 20 個鍵值項目，每個鍵最多可以包含 50 個字元，每個值最多可以包含 500 個字元。這些與用於 Xcode 建構中繼資料的伺服器端限制相同。套件在發送報告前會跳過無效標籤以及過大或空白的中繼資料項目，因此無效設定不會阻止其餘建構洞察報告被儲存。對於不符合標籤限制的値，請使用鍵值中繼資料。

自訂中繼資料附加在建構上，而非測試執行上。

專案成員可以在儀表板中看到自訂中繼資料。請勿將其用於憑證、存取權杖或其他敏感資料。Tuist 會保留 Mix 建構資料（包括此中繼資料）90 天。詳情請參閱 <.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link>。

## 疑難排解 {#troubleshooting}

報告絕不會改變你的建構結果：如果無法發送報告，建構仍會照常完成，且不會列印任何內容。若要查看為何未發送報告，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
