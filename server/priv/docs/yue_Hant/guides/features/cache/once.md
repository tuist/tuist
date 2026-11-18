---
{
  "title": "Once 快取",
  "titleTemplate": ":title · 快取 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的遠端快取，喺開發人員機器同 CI 之間共用 Once action 嘅結果。"
}
---
# Once 快取 {#once-cache}

Once 可以喺本地重用結果，但開發者嘅本地快取唔會分享畀隊友或者全新嘅 CI 工作節點。Tuist 提供共享遠端快取，令相同嘅工作只需要喺一部機器上執行一次。

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

使用 `once auth login --provider tuist` 進行身份驗證。無需安裝 Tuist 可執行檔或額外嘅快取插件。同一個提供者支援 [可快取腳本](https://buildonce.dev/docs/guide/scripted/caching) 同 [圖表目標](https://buildonce.dev/docs/guide/graph)。

只有被 Once 聲明為可快取嘅工作先可以重用。聲明工作所依賴嘅輸入、輸出同環境；配置遠端快取並唔會令任意命令變得可重現。

## 驗證共享重用 {#verify-shared-reuse}

喺兩部具有相同輸入同配置嘅機器上運行相同嘅可快取腳本或圖表目標：

```bash
once build MyApplication
```

第一部機器會填充共享快取。喺第二部機器上，如果其本地快取未見過該結果，出現快取命中並恢復輸出就確認咗遠端重用。淨係喺第一部機器上重複執行命令只能證明本地命中，並唔代表結果由 Tuist 提供。

## 檢查快取活動 {#inspect-cache-activity}

喺你嘅 Tuist 專案中開啟 **Once Cache**，以檢查動作快取命中、傳輸、延遲同吞吐量。開啟某次運行嘅 **Cache** 視圖，以檢查其報告嘅動作決策同內容對象活動。

動作結果同內容對象回答唔同嘅問題：缺少動作結果表示 Once 必須執行該工作，而內容對象請求則係傳輸輸入或輸出。唔好將 blob 下載視為已執行嘅動作或動作快取命中。

如需查看運行嘅動作圖同結構化錯誤，請參閱 <.localized_link href="/guides/features/build-insights/once">Once 構建洞察</.localized_link>。

## 持續整合 {#continuous-integration}

使用 `TUIST_TOKEN` 或 Once 嘅無頭 OIDC 登入，詳情請參閱 <.localized_link href="/guides/integrations/continuous-integration#once">Once 於持續整合</.localized_link>。切勿將憑證放入 `once.toml`。

帳戶嘅 <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">快取上傳政策</.localized_link> 決定咗誰可以發布結果。只讀開發者可以消耗 CI 產生嘅條目，而無需成為快取寫入者。

請參閱 [Once 嘅 Tuist 整合](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery) 以了解連接重試同故障排除。重試並唔會令中斷嘅上傳變為可恢復。
