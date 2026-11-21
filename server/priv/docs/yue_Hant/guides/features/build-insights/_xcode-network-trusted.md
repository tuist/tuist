## 喺私人網絡進行免憑證報告 {#network-trusted-publishing}

自託管部署可以允許開發人員無需登入即可發布已完成嘅報告。營運者必須喺實例上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true`，並按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自託管指南</.localized_link> 所述重新啟動。這適用於每個受支援嘅項目；儀表板中並無相關設定。請喺你嘅 scheme post-action 或終端機所用嘅環境中設定自託管 URL 同項目。當缺少憑證時，CLI 會自動偵測實例政策：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

當確實缺少憑證時，活動日誌同 XCResult bundles 會喺本地解析並作為結構化報告發送。不會提交原始歸檔、附件、覆蓋率/歷史記錄上傳、遠程處理器、分片參考或選擇性執行證據。報告仍然可見，但無法更新已驗證嘅測試用例狀態或觸發隔離/失敗自動化流程。儀表板同其他特權命令仍然需要登入。除非實例單獨啟用網絡可信緩存訪問或已配置憑證，否則請保持緩存集成禁用。

現有憑證仍然保持已驗證狀態。無效、損壞、空白或被拒絕刷新嘅憑證會以安全方式失敗並保留喺磁盤上，因此後續命令不會無聲地變成未簽名狀態。請重新登入或明確登出作為 deliberate 恢復操作。喺升級免憑證客戶端之前，請將每個服務器副本升級至支持發現功能嘅版本，並配置最終服務器 URL 而不使用重定向。較舊嘅不支持發現功能嘅服務器、禁用嘅實例以及發現失敗仍然需要身份驗證。無需客戶端選擇加入。獨立設定 `TUIST_ACTOR_ID=""` 以省略配置嘅 actor claim；已驗證嘅憑證身份不受影響。
