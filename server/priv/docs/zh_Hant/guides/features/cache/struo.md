---
{
  "title": "Struo 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的遠端快取，在開發者機器與 CI 之間共享 Struo 動作結果。"
}
---
# Struo 快取 {#struo-cache}

<a id="once-cache"></a>

Struo 可以在本機重複使用結果，但開發人員的本機快取無法與團隊成員或全新的 CI 工作節點共用。Tuist 提供共用的遠端快取，讓相符的工作只需在一台機器上執行一次。

## 設定 {#setup}

完成<.localized_link href="/guides/get-started/struo-project#connect-the-project">開始使用 Struo</.localized_link>，然後檢查儲存庫中 `struo.toml` 的快取綁定：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

使用 `struo auth login --provider tuist` 進行驗證。不需要 Tuist 執行檔或額外的快取外掛程式。相同的提供者支援[可快取的指令碼](https://struo.run/docs/guide/scripted/caching)和[圖表目標](https://struo.run/docs/guide/graph)。

只有由 Struo 宣告為可快取的工作才能重複使用。請宣告工作所依賴的輸入、輸出和環境；設定遠端快取並不會讓任意指令變得可重複執行。

## 驗證共用重複使用 {#verify-shared-reuse}

在兩台具有相符輸入和設定的機器上，執行相同的可快取指令碼或圖表目標：

```bash
struo build MyApplication
```

第一台機器會填充共用快取。在第二台本機快取尚未見過該結果的機器上，命中並還原輸出可確認遠端重複使用。僅在第一台機器上重複執行指令只能證明本機命中，而非 Tuist 提供了結果。

## 檢查快取活動 {#inspect-cache-activity}

在 Tuist 專案中開啟**Struo Cache**以檢查動作快取命中、傳輸、延遲和吞吐量。開啟執行的**Cache**檢視畫面，以檢查其回報的動作決策和內容物件活動。

動作結果和內容物件回答不同的問題：缺少動作結果表示 Struo 必須執行該工作，而內容物件請求則傳輸輸入或輸出。請勿將 blob 下載視為已執行的動作或動作快取命中。

如需執行的動作圖表和結構化錯誤，請參閱<.localized_link href="/guides/features/build-insights/struo">Struo 建置洞察</.localized_link>。

## 持續整合 {#continuous-integration}

使用 `TUIST_TOKEN` 或 Struo 的無頭 OIDC 登入，如<.localized_link href="/guides/integrations/continuous-integration#struo">持續整合中的 Struo</.localized_link>所述。請勿將憑證放入 `struo.toml`。

帳戶的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link>決定誰可以發布結果。唯讀開發人員可以使用 CI 產生的項目，而無需成為快取寫入者。

如需連線重試和疑難排解，請參閱[Struo 的 Tuist 整合](https://struo.run/docs/guide/infrastructure/tuist#connection-recovery)。重試不會讓中斷的上傳變為可恢復。
