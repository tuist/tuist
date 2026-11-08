---
{
  "title": "Once 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的遠端快取，在開發者機器與 CI 之間共享 Once 動作的結果。"
}
---
# Once 快取 {#once-cache}

Once 可在本機重複使用結果，但開發者的本機快取無法與團隊成員或全新的 CI 工作節點共用。Tuist 提供共用的遠端快取，讓相符的工作只需在一台機器上執行。

## 設定 {#setup}

完成<.localized_link href="/guides/get-started/once-project#connect-the-project">開始使用 Once</.localized_link>，然後檢查儲存庫中 `once.toml` 的快取綁定：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

使用 `once auth login --provider tuist` 進行驗證。不需要 Tuist 執行檔或額外的快取外掛程式。同一個提供者支援[可快取的指令碼](https://buildonce.dev/docs/guide/scripted/caching)和[圖表目標](https://buildonce.dev/docs/guide/graph)。

只有由 Once 宣告為可快取的工作才能重複使用。請宣告工作所依賴的輸入、輸出與環境；設定遠端快取並不會讓任意指令具備可重現性。

## 驗證共用重複使用 {#verify-shared-reuse}

在兩台具有相符輸入與設定的機器上，執行相同的可快取指令碼或圖表目標：

```bash
once build MyApplication
```

第一台機器會填入共用快取。在第二台本機快取尚未見過該結果的機器上，快取命中與還原的輸出可確認遠端重複使用。僅在第一台機器上重複執行指令只能證明本機命中，而非 Tuist 提供了結果。

## 檢查快取活動 {#inspect-cache-activity}

在你的 Tuist 專案中開啟**Once Cache**，以檢查動作快取命中、傳輸、延遲與吞吐量。開啟某次執行的**Cache**檢視畫面，以檢查其回報的動作決策與內容物件活動。

動作結果與內容物件回答不同的問題：缺少動作結果表示 Once 必須執行該工作，而內容物件請求則會傳輸輸入或輸出。請勿將 blob 下載視為已執行的動作或動作快取命中。

如需該執行的動作圖與結構化錯誤，請參閱<.localized_link href="/guides/features/build-insights/once">Once 建置洞察</.localized_link>。

## 持續整合 {#continuous-integration}

使用 `TUIST_TOKEN` 或 Once 的無頭 OIDC 登入，如<.localized_link href="/guides/integrations/continuous-integration#once">Once 於持續整合</.localized_link>所述。請勿將憑證放入 `once.toml`。

帳戶的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>決定誰可以發布結果。唯讀開發者可以使用 CI 產生的項目，而無需成為快取寫入者。

請參閱[Once 的 Tuist 整合](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery)以了解連線重試與疑難排解。重試不會讓中斷的上傳可恢復。
