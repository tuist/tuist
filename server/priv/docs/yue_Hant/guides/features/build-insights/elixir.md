---
{
  "title": "Elixir 建置分析",
  "titleTemplate": ":title · 建置分析 · 功能 · 指南 · Tuist",
  "description": "追蹤你的 Elixir 專案使用 Mix 編譯所需時間、警告訊息，以及拖慢建置速度的檔案。"
}
---
# Elixir 構建洞察 {#elixir-build-insights}

Tuist 的 Hex 套件可以將構建分析數據發送到 Tuist。構建時間、文件之間的依賴關係圖，以及兩者隨時間的變化，為你提供優化構建圖並充分利用編譯環境中所有核心所需的資訊。

> [!IMPORTANT] REQUIREMENTS
> - 完成<.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 報告你的構建 {#report-your-builds}

共享設置會安裝編譯集成。繼續使用你慣用的命令：

```bash
mix compile
```

該集成涵蓋 `mix compile` 以及由其他任務觸發的每次編譯，例如 `mix test` 或 `mix phx.server`。如果編譯發現無需執行任何操作，則不會報告，因此儀表板僅列出實際執行了工作的構建。

## 報告參與者聲明 {#report-actor-claim}

只有當你明確配置標籤時，Mix 構建和測試報告請求才會包含可選的 `x-tuist-actor-id` 標頭。將 `TUIST_ACTOR_ID` 設置為組織範圍內的標籤，或在項目的 `tuist` 配置中添加 `actor_id: "developer-label"`。解析優先順序為：環境變量、運行時 `:actor_id` 選項，然後是項目配置。默認情況下不發送標籤，且套件不會檢測操作系統用戶名。固定的項目標籤適用於所有使用該配置的人。空值或無效的重寫會省略聲明而不是回退；這不會移除基於憑證的已驗證身份。如果自定義代理拒絕陌生的標頭，請使用 `TUIST_ACTOR_ID=""` 選擇退出。

標識符必須是 1–128 字節的非空格可打印 ASCII 字符。無效的重寫會被省略而不進行回退。已驗證的個人憑證具有優先權；其他客戶端報告的標識符顯示為**未驗證**，從不授權訪問，也從不自動鏈接到用戶。任何可以查看項目報告的人都能看到這些標識符，包括項目公開時的公眾觀眾，並且它們包含在數據導出中，因此不要包含機密信息。舊服務器會忽略可選標頭，而新服務器接受沒有該標頭的舊客戶端。沒有標識符的新共享令牌報告顯示**未知**，而不是發布組織；歷史報告保留其先前的歸屬。默認情況下，構建和測試報告需要身份驗證。自託管安裝可以按照下述方式明確啟用無憑證報告。

## 私有網絡上的無憑證報告 {#network-trusted-publishing}

運營者在實例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 並按照<.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link>中的描述重啟後，配置你的目標地址。當缺少憑證時，SDK 會自動發現實例是否允許無憑證報告。實例設置涵蓋每個支持的項目，且儀表板上沒有切換開關：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` 和 `mix tuist.test` 會在憑證確實缺失且發現確認服務器允許的情況下，無需登錄即可發布結構化報告。不需要客戶端標誌或項目選擇加入。現有憑證（包括提供的 CI OIDC 身份）會被使用或拒絕，從不會被忽略以降級為未簽名報告。僅包含空格的 `TUIST_TOKEN` 是一個錯誤。空的 `TUIST_TOKEN` 可以回退到有效的存儲憑證或提供的 OIDC，過期的存儲憑證也可以回退到提供的 OIDC；這兩種路徑都保持身份驗證狀態，從不啟用未簽名報告。無法使用的憑證會被保留，並在沒有成功的身份驗證回退時失敗。在升級無憑證客戶端之前，請將每個服務器副本升級到支持發現的版本；不支持發現的舊服務器、已禁用的實例以及發現失敗的情況仍然需要身份驗證。

未簽名運行屬於遙測數據，並非可信的閃爍測試、隔離、覆蓋率或選擇性執行證據。分片規劃、構建存檔以及覆蓋率/構件端點仍然需要憑證。獨立設置 `TUIST_ACTOR_ID=""` 以省略配置的參與者聲明；已驗證的憑證身份不受影響。

## 追蹤內容 {#what-is-tracked}

對於每次構建，套件會收集：
- 其持續時間、是否成功，以及運行的 Elixir、Erlang/OTP 和 Mix 環境
- 每個警告和錯誤，及其所在的文件和行號
- 每個文件的編譯耗時，以及它定義的模塊
- 每個文件依賴的文件，以及是在編譯時還是僅在運行時需要它們
- 除了編譯文件之外構建執行的操作，例如類型檢查、寫入磁盤以及其他 Mix 編譯器
- 構建期間機器的處理器、內存、網絡和磁盤使用情況
- 分支和提交，以及在持續集成中的提供商和運行

## 找出拖慢構建的因素 {#find-what-slows-a-build-down}

在儀表板上從**構建 → 構建運行**打開一個構建。構建、其診斷計數以及依賴緩存摘要也可通過 `tuist build mix list` 和 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds`，以及 `list_mix_builds` 和 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 獲取。

**概覽**標籤頁列出構建編譯的文件。你可以按模塊對它們進行分組、搜索，並按以下方式排序：
- **編譯時長**，用於找出本身較慢的文件。
- **編譯時依賴者**，即在該文件編譯完成之前無法編譯的文件數量。擁有許多依賴者的慢速文件會阻礙構建的其餘部分，更改它會導致重新編譯所有依賴者。
- **編譯時依賴項**，即該文件等待的文件數量。

![Phoenix 應用程序的 Mix 構建概覽](/images/guides/features/elixir/build.png)

**時間線**標籤頁顯示同一構建隨時間的情況：哪些文件並行編譯、構建在何處進行類型檢查和寫入磁盤，以及機器在每個時刻的狀態。只有一條欄位的區間表示構建無法利用其可用的核心。

![Phoenix 應用程序完整 Mix 構建的時間線](/images/guides/features/elixir/build-timeline.png)

**警告**和**錯誤**標籤頁列出構建的診斷信息。

## 自定義元數據 {#custom-metadata}

將標籤和鍵值數據附加到 Mix 構建，以區分來自不同團隊、硬件或工作流的運行。兩者都會出現在每個構建的詳情頁面上。

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

兩處的標籤會合併。如果兩處配置了相同的鍵，環境變量中的值優先。

標籤只能包含字母、數字、連字符和下劃線。一個構建最多可以有 50 個標籤，每個標籤最多 50 個字符。一個構建最多可以有 20 個鍵值條目，每個鍵最多 50 個字符，每個值最多 500 個字符。這些與 Xcode 構建元數據使用的服務器端限制相同。在發送報告之前，包會跳過無效的標籤以及過大或空的元數據條目，因此無效的配置不會阻止剩餘的構建洞察報告被存儲。對於不符合標籤約束的值，請使用鍵值元數據。

自定義元數據附加到構建，而不是測試運行。

項目成員可以在儀表板上查看自定義元數據。不要將其用於憑證、訪問令牌或其他敏感數據。Tuist 保留 Mix 構建數據（包括此元數據）90 天。詳情請參閱<.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>。

## 疑難解答 {#troubleshooting}

報告從不改變你的構建結果：如果無法發送報告，構建仍會照常完成，且不會打印任何內容。要查看報告未發送的原因，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
