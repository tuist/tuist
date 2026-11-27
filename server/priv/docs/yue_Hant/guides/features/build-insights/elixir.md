---
{
  "title": "Elixir 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "追蹤你的 Elixir 專案使用 Mix 編譯所需時間、警告訊息，以及拖慢構建速度的檔案。"
}
---
# Elixir 建置分析 {#elixir-build-insights}

Tuist 嘅 Hex 套件可以將建置分析數據傳送到 Tuist。建置時間、檔案之間嘅依賴關係圖，以及兩者隨時間嘅變化，令你得以優化建置圖，並充分利用編譯環境中可用嘅所有核心。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 回報你嘅建置 {#report-your-builds}

共用設定會安裝編譯整合功能。繼續使用你慣用嘅指令：

```bash
mix compile
```

整合功能涵蓋 `mix compile` 以及其他任務觸發嘅每次編譯，例如 `mix test` 或 `mix phx.server`。如果編譯發現無事可做，就不會上報，因此儀表板只會列出實際執行工作嘅建置。

## 回報參與者聲明 {#report-actor-claim}

Mix 建置同測試回報請求只係喺你明確設定標籤時，先會包含可選嘅 `x-tuist-actor-id` 標頭。將 `TUIST_ACTOR_ID` 設定為組織範圍內嘅標籤，或者將 `actor_id: "developer-label"` 加入專案嘅 `tuist` 設定。解析順序優先採用環境變數，其次係執行階段 `:actor_id` 選項，最後先係專案設定。預設情況下不會傳送任何標籤，而且套件不會偵測作業系統使用者名稱。固定嘅專案標籤適用於所有使用該設定嘅人。空白或無效嘅覆寫會省略聲明而唔會回退；這並唔會移除基於憑證嘅已驗證身分。如果自訂代理伺服器拒絕不熟悉嘅標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

識別碼必須係 1–128 位元組嘅非空格可列印 ASCII 字元。無效嘅覆寫會被省略而唔會回退。已驗證嘅個人憑證具有優先權；其他由客戶端報告嘅識別碼會顯示為 **未驗證**，永遠唔會授權存取，亦都唔會自動連結到使用者。任何能夠檢視專案報告嘅人都可以看到呢啲識別碼，包括當專案公開時嘅公眾檢視者，而且佢哋會被包含喺數據匯出中，所以唔好包含機密資料。舊版伺服器會忽略可選標頭，而新版伺服器會接受沒有該標頭嘅舊版客戶端。沒有識別碼嘅新共用令牌回報會顯示 **未知**，而唔係發佈組織；歷史報告會保留其先前嘅歸屬。預設情況下，建置同測試回報需要身份驗證。自託管安裝可以按照下述方式明確啟用免憑證回報。

## 喺私人網絡上進行免憑證回報 {#network-trusted-publishing}

當營運人員按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link> 所述喺實例上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動後，請設定你嘅目標位置。SDK 會自動偵測當缺少憑證時，實例是否允許免憑證回報。實例設定涵蓋所有受支援嘅專案，並且儀表板上沒有切換開關：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

當確實缺少憑證且偵測確認伺服器允許時，`mix tuist.compile` 同 `mix tuist.test` 會喺無需登入嘅情況下發佈結構化報告。不需要客戶端標誌或專案選擇加入。現有憑證（包括提供嘅 CI OIDC 身分）會被使用或被拒絕，但絕不會被忽略以降級為未簽名回報。僅包含空白字符嘅 `TUIST_TOKEN` 係錯誤。空白嘅 `TUIST_TOKEN` 可以回退到有效嘅儲存憑證或提供嘅 OIDC，而過時嘅儲存憑證可以回退到提供嘅 OIDC；兩條路徑都保持身份驗證狀態，永遠唔會啟用未簽名回報。無法使用嘅憑證會被保留，並且當沒有成功嘅身份驗證回退時會失敗。喺升級免憑證客戶端之前，請將每個伺服器副本升級到支援偵測嘅版本；沒有偵測功能嘅舊版伺服器、已停用嘅實例以及偵測失敗仍然需要身份驗證。

未簽名運行係遙測數據，唔係可信嘅不穩定性、隔離、覆蓋率或選擇性執行證據。分片規劃、建置存檔以及覆蓋率/產物端點仍然需要憑證。獨立設定 `TUIST_ACTOR_ID=""` 以省略已設定嘅參與者聲明；已驗證嘅憑證身分不受影響。

## 追蹤內容 {#what-is-tracked}

對於每次建置，套件會收集：
- 其持續時間、是否成功，以及運行時所用嘅 Elixir、Erlang/OTP 同 Mix 環境
- 每個警告同錯誤，連同其檔案同行號
- 每個檔案編譯所需嘅時間，以及其所定義嘅模組
- 每個檔案依賴嘅檔案，以及係咪喺編譯時需要佢哋，定係只係喺運行時需要
- 除咗編譯檔案之外，建置還做咗乜嘢，例如類型檢查、寫入磁盤，以及其他 Mix 編譯器
- 建置期間機器嘅處理器、記憶體、網絡同磁盤使用情況
- 分支同提交，以及喺持續集成中，提供者同運行

## 找出拖慢建置嘅原因 {#find-what-slows-a-build-down}

喺儀表板上從 **建置 → 建置運行** 開啟一個建置。建置、其診斷計數同依賴快取摘要亦可透過 `tuist build mix list` 同 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds`，以及 `list_mix_builds` 同 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 取得。

**概覽** 分頁列出建置編譯嘅檔案。你可以按模組將佢哋分組、搜尋佢哋，並按以下方式排序：
- **編譯持續時間**，以找出本身較慢嘅檔案。
- **編譯時依賴者**，即係必須等到此檔案編譯完成先至可以編譯嘅檔案數量。一個帶有許多依賴者嘅慢速檔案會阻礙剩餘嘅建置，更改它會導致重新編譯所有依賴者。
- **編譯時依賴項**，即係此檔案等待嘅檔案數量。

![Phoenix 應用程式 Mix 建置概覽](/images/guides/features/elixir/build.png)

**時間軸** 分頁顯示同一建置隨時間嘅變化：哪些檔案並行編譯、建置喺邊度進行類型檢查同寫入磁盤，以及機器喺每個時刻嘅狀況。只有一條欄嘅時段表示建置無法使用其擁有嘅核心。

![Phoenix 應用程式完整 Mix 建置時間軸](/images/guides/features/elixir/build-timeline.png)

**警告** 同 **錯誤** 分頁列出建置嘅診斷信息。

## 自訂元數據 {#custom-metadata}

將標籤同鍵值數據附加到 Mix 建置，以區分來自不同團隊、硬件或工作流程嘅運行。兩者都會出現喺每個建置嘅詳情頁面。

使用環境變數設定元數據：

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

你亦都可以喺 `mix.exs` 中設定元數據：

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

兩處嘅標籤會合併。如果同一個鍵喺兩處都有設定，環境變數中嘅值會優先。

標籤只能包含字母、數字、連字號同下劃線。一個建置最多可以有 50 個標籤，每個標籤最多可以包含 50 個字符。一個建置最多可以有 20 個鍵值條目，每個鍵最多可以包含 50 個字符，每個值最多可以包含 500 個字符。呢啲係同 Xcode 建置元數據使用嘅相同伺服器端限制。套件喺發送報告之前會跳過無效標籤同過大或空嘅元數據條目，所以無效配置唔會阻止剩餘嘅建置洞察報告被儲存。對於唔符合標籤約束嘅值，請使用鍵值元數據。

自訂元數據係附加到建置，而唔係測試運行。

自訂元數據喺儀表板上對項目成員可見。唔好將佢用於憑證、訪問令牌或其他敏感數據。Tuist 會保留 Mix 建置數據（包括此元數據）90 日。詳情請參閱 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。

## 疑難排解 {#troubleshooting}

報告永遠唔會改變你建置嘅結果：如果報告無法發送，建置會照常完成且唔會打印任何內容。要查看報告為何未發送，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
