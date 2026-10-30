---
{
  "title": "Elixir 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "追蹤你的 Elixir 專案使用 Mix 編譯所需的時間、警告，以及拖慢建置進度的檔案。"
}
---
# Elixir 構建洞察 {#elixir-build-insights}

Tuist 嘅 Hex 套件可以將構建分析數據發送到 Tuist。構建時間、文件之間嘅依賴關係圖，以及兩者隨時間嘅變化，為你提供優化構建圖所需嘅資訊，並充分利用編譯環境中可用嘅所有核心。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 報告你嘅構建 {#report-your-builds}

共享設置會安裝編譯集成。繼續使用你慣用嘅命令：

```bash
mix compile
```

集成涵蓋 `mix compile` 以及由其他任務觸發嘅每次編譯，例如 `mix test` 或 `mix phx.server`。如果編譯發現無事可做，則不會報告，因此儀表板只會列出實際執行工作嘅構建。

## 報告 Actor 聲明 {#report-actor-claim}

只有當你明確配置標籤時，Mix 構建和測試報告請求才會包含可選嘅 `x-tuist-actor-id` 標頭。將 `TUIST_ACTOR_ID` 設置為組織範圍內嘅標籤，或者將 `actor_id: "developer-label"` 添加到項目嘅 `tuist` 配置中。解析優先順序為：環境變量，然後是運行時 `:actor_id` 選項，最後是項目配置。默認情況下不會發送標籤，且套件不會檢測操作系統用戶名。固定嘅項目標籤適用於使用該配置嘅所有人。空值或無效嘅覆蓋會省略聲明而不是回退；這不會移除基於憑證嘅已驗證身份。如果自定義代理拒絕不熟悉嘅標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

標識符必須係 1–128 字節嘅非空格可打印 ASCII 字符。無效嘅覆蓋會被省略而不會回退。已驗證嘅個人憑證具有優先權；其他客戶端報告嘅標識符顯示為 **未驗證**，從不授權訪問，也從不自動鏈接到用戶。任何可以查看項目報告嘅人都可以看到這些標識符，包括項目公開時嘅公眾觀眾，並且它們包含在數據導出中，因此不要包含秘密。舊服務器會忽略可選標頭，新服務器接受沒有該標頭嘅舊客戶端。沒有標識符嘅新共享令牌報告顯示 **未知**，而不是發布組織；歷史報告保留其先前嘅歸屬。默認情況下，構建和測試報告需要身份驗證。自託管安裝可以按照下面描述嘅方式明確啟用無憑證報告。

## 私有網絡上嘅無憑證報告 {#network-trusted-publishing}

當運營者在實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link> 中所述重啟後，配置你嘅目標地址。SDK 會自動發現當缺少憑證時實例是否允許無憑證報告。實例設置涵蓋每個受支持嘅項目，並且儀表板上沒有切換開關：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` 和 `mix tuist.test` 會在憑證確實缺失且發現確認服務器允許時，無需登錄即可發布結構化報告。不需要客戶端標誌或項目選擇加入。現有憑證（包括提供嘅 CI OIDC 身份）會被使用或拒絕，從不會被忽略以降級為無簽名報告。僅包含空白字符嘅 `TUIST_TOKEN` 係錯誤。空嘅 `TUIST_TOKEN` 可以回退到有效嘅存儲憑證或提供嘅 OIDC，過期嘅存儲憑證可以回退到提供嘅 OIDC；兩種路徑都保持身份驗證狀態，從不啟用無簽名報告。無法使用嘅憑證會被保留，並在沒有成功嘅身份驗證回退時失敗。在升級無憑證客戶端之前，先將每個服務器副本升級到支持發現功能嘅版本；不支持發現功能嘅舊服務器、禁用嘅實例以及發現失敗仍然需要身份驗證。

無簽名運行係遙測數據，不是可信嘅不穩定性、隔離、覆蓋率或選擇性執行證據。分片規劃、構建存檔以及覆蓋率/構件端點仍然需要憑證。獨立設置 `TUIST_ACTOR_ID=""` 以省略配置嘅 actor 聲明；已驗證嘅憑證身份不受影響。

## 追蹤內容 {#what-is-tracked}

對於每次構建，套件會收集：
- 其持續時間、是否成功，以及運行時使用嘅 Elixir、Erlang/OTP 和 Mix 環境
- 每個警告和錯誤，及其文件和行號
- 每個文件編譯所需嘅時間，以及它定義嘅模塊
- 每個文件依賴嘅文件，以及係在編譯時還係僅在運行時需要它們
- 除編譯文件外構建執行嘅操作，例如類型檢查、寫入磁盤以及其他 Mix 編譯器
- 構建期間機器嘅處理器、內存、網絡和磁盤使用情況
- 分支和提交，以及在持續集成中嘅提供商和運行

## 找出拖慢構建速度嘅原因 {#find-what-slows-a-build-down}

從儀表板上嘅 **構建 → 構建運行** 打開一個構建。構建、它們嘅診斷計數以及它們嘅依賴緩存摘要也可以通過 `tuist build mix list` 和 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds` 以及 `list_mix_builds` 和 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 獲得。

**概覽** 標籤頁列出構建編譯嘅文件。你可以按模塊對它們進行分組、搜索它們，並按以下方式排序：
- **編譯持續時間**，用於找出本身較慢嘅文件。
- **編譯時依賴者**，即在此文件編譯完成之前無法編譯嘅文件數量。一個較慢且擁有許多依賴者嘅文件會阻礙其餘構建，更改它會導致重新編譯所有依賴者。
- **編譯時依賴項**，即此文件等待嘅文件數量。

![Phoenix 應用程序 Mix 構建概覽](/images/guides/features/elixir/build.png)

**時間線** 標籤頁顯示同一構建隨時間嘅變化：哪些文件並行編譯，構建在哪裡進行類型檢查和寫入磁盤，以及機器在每個時刻嘅狀態。只有一條條碼嘅時段表示構建無法利用其擁有嘅核心。

![Phoenix 應用程序完整 Mix 構建時間線](/images/guides/features/elixir/build-timeline.png)

**警告** 和 **錯誤** 標籤頁列出構建嘅診斷信息。

## 自定義元數據 {#custom-metadata}

將標籤和鍵值數據附加到 Mix 構建，以區分來自不同團隊、硬件或工作流嘅運行。兩者都會出現在每個構建嘅詳情頁面上。

使用環境變量設置元數據：

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

你也可以在 `mix.exs` 中配置元數據：

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

兩處嘅標籤會合併。如果同一個鍵在兩處都有配置，環境變量中嘅值優先。

標籤只能包含字母、數字、連字符同下劃線。一個構建最多可以有 50 個標籤，每個標籤最多 50 個字符。一個構建最多可以有 20 個鍵值對條目，每個鍵最多 50 個字符，每個值最多 500 個字符。呢啲限制同 Xcode 構建元數據使用嘅服務器端限制相同。套件在發送報告之前會跳過無效標籤以及過大或空嘅元數據條目，所以無效配置唔會阻止其餘構建洞察報告被存儲。對於唔符合標籤約束嘅值，請使用鍵值元數據。

自定義元數據係附加到構建，而唔係測試運行。

項目成員可以在儀表板上看到自定義元數據。唔好將佢用於憑證、訪問令牌或其他敏感數據。Tuist 會保留 Mix 構建數據（包括呢啲元數據）90 日。詳情請參閱 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。

## 疑難排解 {#troubleshooting}

報告永遠唔會改變你構建嘅結果：如果報告無法發送，構建會照常完成，並且唔會打印任何內容。要查看報告為何未發送，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
