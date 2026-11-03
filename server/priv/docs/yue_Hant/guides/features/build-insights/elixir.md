---
{
  "title": "Elixir 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "追蹤你的 Elixir 專案使用 Mix 編譯所需時間、警告訊息，以及拖慢建置速度的檔案。"
}
---
# Elixir 建構分析 {#elixir-build-insights}

Tuist 嘅 Hex 套件可以將建構分析數據傳送到 Tuist。建構時間、檔案之間嘅依賴圖，以及兩者隨時間嘅變化，為你提供優化建構圖所需嘅資訊，並充分利用編譯環境中可用嘅所有核心。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 報告你嘅建構 {#report-your-builds}

共享設定會安裝編譯整合功能。繼續使用你慣常嘅指令：

```bash
mix compile
```

整合涵蓋 `mix compile` 以及由其他任務觸發嘅每次編譯，例如 `mix test` 或 `mix phx.server`。如果編譯發現無事可做，則不會報告，因此儀表板只會列出實際執行工作嘅建構。

## 報告參與者聲明 {#report-actor-claim}

只有當你明確配置標籤時，Mix 建構同測試報告請求才會包含可選嘅 `x-tuist-actor-id` 標頭。將 `TUIST_ACTOR_ID` 設定為組織範圍內嘅標籤，或者將 `actor_id: "developer-label"` 加入項目嘅 `tuist` 配置中。解析優先順序為環境變數，然後係運行時 `:actor_id` 選項，最後係項目配置。預設情況下不會發送標籤，而且套件亦不會偵測作業系統用戶名。固定嘅項目標籤適用於所有使用該配置嘅人。空白或無效嘅覆寫會省略聲明而唔會回退；這並不會移除基於憑證嘅已驗證身份。如果自定義代理拒絕不熟悉嘅標頭，請使用 `TUIST_ACTOR_ID=""` 退出。

識別碼必須係 1–128 字節嘅非空格可打印 ASCII。無效嘅覆寫會被省略而唔會回退。已驗證嘅個人憑證具有優先權；其他客戶端報告嘅識別碼會顯示為 **未驗證**，永遠唔會授權訪問，亦永遠唔會自動連結到用戶。任何可以查看項目報告嘅人都可以看到這些識別碼，包括項目公開時嘅公眾觀眾，並且它們會包含在數據導出中，所以切勿包含機密資料。舊伺服器會忽略可選標頭，而新伺服器會接受沒有該標頭嘅舊客戶端。沒有識別碼嘅新共享令牌報告會顯示 **未知**，而唔係發布組織；歷史報告會保留其先前嘅歸屬。預設情況下，建構同測試報告需要身份驗證。自託管安裝可以按照下述方式明確啟用無需憑證嘅報告。

## 私有網絡上嘅無需憑證報告 {#network-trusted-publishing}

當操作員按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link> 中所述，在實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並重新啟動後，請配置你嘅目標。SDK 會自動偵測當缺少憑證時，實例是否允許無需憑證嘅報告。實例設置涵蓋每個受支持嘅項目，並且儀表板上沒有切換開關：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` 同 `mix tuist.test` 會在憑證確實缺失且偵測確認伺服器允許時，發布結構化報告而無需登入。不需要客戶端標誌或項目選擇加入。現有憑證（包括提供嘅 CI OIDC 身份）會被使用或拒絕，絕不會被忽略以降級為未簽名報告。僅包含空白字符嘅 `TUIST_TOKEN` 係錯誤。空白嘅 `TUIST_TOKEN` 可以回退到有效嘅存儲憑證或提供嘅 OIDC，而過期嘅存儲憑證可以回退到提供嘅 OIDC；兩種路徑都保持身份驗證狀態，永遠唔會啟用未簽名報告。無法使用嘅憑證會被保留，並且當沒有身份驗證回退成功時會失敗。在升級無需憑證嘅客戶端之前，請將每個伺服器副本升級到支持偵測嘅版本；沒有偵測功能嘅舊伺服器、禁用嘅實例以及偵測失敗仍然需要身份驗證。

未簽名運行係遙測數據，並非可信嘅不穩定性、隔離、覆蓋率或選擇性執行證據。分片規劃、建構歸檔以及覆蓋率/構件端點仍然需要憑證。獨立設置 `TUIST_ACTOR_ID=""` 以省略配置嘅參與者聲明；已驗證嘅憑證身份不受影響。

## 追蹤內容 {#what-is-tracked}

對於每次建構，套件會收集：
- 其持續時間、是否成功，以及運行時嘅 Elixir、Erlang/OTP 同 Mix 環境
- 每個警告同錯誤，連同其檔案同行號
- 每個檔案編譯所需嘅時間，以及它定義嘅模組
- 每個檔案依賴嘅檔案，以及係編譯時定係僅在運行時需要它們
- 建構除編譯檔案外所做嘅事情，例如類型檢查、寫入磁盤以及其他 Mix 編譯器
- 建構期間機器嘅處理器、記憶體、網絡同磁盤使用情況
- 分支同提交，以及在持續集成中嘅提供商同運行

## 找出拖慢建構速度嘅原因 {#find-what-slows-a-build-down}

從儀表板上嘅 **建構 → 建構運行** 打開一個建構。建構、它們嘅診斷計數以及它們嘅依賴緩存摘要亦可通過 `tuist build mix list` 同 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds`，以及 `list_mix_builds` 同 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 獲得。

**概覽** 標籤頁列出建構編譯嘅檔案。你可以按模組將它們分組、搜索它們，並按以下方式排序：
- **編譯持續時間**，以找出本身較慢嘅檔案。
- **編譯時依賴者**，即在此檔案編譯完成之前無法編譯嘅檔案數量。一個擁有眾多依賴者嘅慢速檔案會阻礙其餘建構，更改它會導致重新編譯所有依賴者。
- **編譯時依賴項**，即此檔案等待嘅檔案數量。

![Phoenix 應用程式 Mix 建構概覽](/images/guides/features/elixir/build.png)

**時間線** 標籤頁顯示同一建構隨時間嘅變化：哪些檔案並行編譯、建構在哪裡進行類型檢查同寫入磁盤，以及機器在每個時刻嘅狀態。只有一條條紋嘅區段表示建構無法利用其可用核心嘅時期。

![Phoenix 應用程式完整 Mix 建構時間線](/images/guides/features/elixir/build-timeline.png)

**警告** 同 **錯誤** 標籤頁列出建構嘅診斷信息。

## 自定義元數據 {#custom-metadata}

將標籤同鍵值數據附加到 Mix 建構，以區分來自不同團隊、硬件或工作流程嘅運行。兩者都會出現在每個建構嘅詳情頁面。

使用環境變數設置元數據：

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

你亦可以在 `mix.exs` 中配置元數據：

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

兩處嘅標籤會合併。如果同一個鍵喺兩處都有配置，環境變數中嘅值會優先。

標籤只能包含字母、數字、連字符同下劃線。一個建構最多可以有 50 個標籤，每個標籤最多可以包含 50 個字符。一個建構最多可以有 20 個鍵值條目，每個鍵最多可以包含 50 個字符，每個值最多可以包含 500 個字符。呢啲同用於 Xcode 建構元數據嘅服務器端限制相同。套件喺發送報告之前會跳過無效標籤以及過大或空嘅元數據條目，所以無效配置唔會阻止其餘建構洞察報告被儲存。對於唔符合標籤約束嘅值，請使用鍵值元數據。

自定義元數據係附加到建構，而唔係測試運行。

項目成員可以在儀表板上看到自定義元數據。唔好將佢用於憑證、訪問令牌或其他敏感數據。Tuist 會保留 Mix 建構數據（包括呢啲元數據）90 日。詳情請參閱 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。

## 疑難排解 {#troubleshooting}

報告永遠唔會改變你建構嘅結果：如果報告無法發送，建構會照常完成，並且唔會打印任何內容。要查看報告為何未發送，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
