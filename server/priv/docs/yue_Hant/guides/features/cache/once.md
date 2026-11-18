---
{
  "title": "Once 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅遠端快取，喺開發者電腦同 CI 之間共享 Once action 結果。"
}
---
# Once 快取 {#once-cache}

Once 可以喺本地重用結果，但開發者嘅本地快取無法分享俾隊友或全新嘅 CI 工作節點。Tuist 提供共用遙距快取，令相同工作只需喺一部機器上執行一次。

## 設定 {#setup}

完成 <.localized_link href="/guides/get-started/once-project#connect-the-project">開始使用 Once</.localized_link>，然後檢查你儲存庫中 `once.toml` 嘅快取綁定：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

使用 `once auth login --provider tuist` 進行驗證。無需安裝 Tuist 可執行檔或額外嘅快取插件。同一供應商支援 [可快取腳本](https://buildonce.dev/docs/guide/scripted/caching) 同 [圖表目標](https://buildonce.dev/docs/guide/graph)。

只有被 Once 聲明為可快取嘅工作先可以被重用。聲明工作所依賴嘅輸入、輸出同環境；配置遙距快取並不會令任意命令變得可重現。

## 驗證共用重用 {#verify-shared-reuse}

喺兩部具有匹配輸入同配置嘅機器上執行相同嘅可快取腳本或圖表目標：

```bash
once build MyApplication
```

第一部機器會填充共用快取。喺第二部機器上，如果其本地快取未曾見過該結果，出現快取命中並恢復輸出就確認咗遙距重用。僅喺第一部機器上重複執行命令只能證明本地命中，並不代表 Tuist 提供咗結果。

## 檢查快取活動 {#inspect-cache-activity}

喺你嘅 Tuist 專案中開啟 **Once Cache** 以檢查動作快取命中、傳輸、延遲同吞吐量。開啟某個運行嘅 **快取** 視圖以檢查其報告嘅動作決策同內容物件活動。

動作結果同內容物件回答唔同嘅問題：缺少動作結果意味著 Once 必須執行工作，而內容物件請求則係傳輸輸入或輸出。切勿將 blob 下載視為已執行嘅動作或動作快取命中。

如需查看運行嘅動作圖表同結構化錯誤，請參閱 <.localized_link href="/guides/features/build-insights/once">Once 構建洞察</.localized_link>。

## 持續整合 {#continuous-integration}

使用 `TUIST_TOKEN` 或 Once 嘅無頭 OIDC 登入，詳情請參閱 <.localized_link href="/guides/integrations/continuous-integration#once">Once 於持續整合</.localized_link>。切勿將憑證放入 `once.toml`。

帳戶嘅 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link> 決定咗誰可以發布結果。唯讀開發者可以使用 CI 產生嘅條目，而無需成為快取寫入者。

請參閱 [Once 嘅 Tuist 整合](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery) 以了解連接重試同故障排除。重試並不會令中斷嘅上傳變得可恢復。
