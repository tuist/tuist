## 在私有網路上進行免憑證報告 {#network-trusted-publishing}

自行託管的部署可讓開發人員在不登入的情況下發布已完成的報告。營運者必須在執行個體上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true`，並依照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自行託管指南</.localized_link> 所述重新啟動。此設定適用於所有支援的專案；儀表板中沒有相關設定。請在您的 scheme post-action 或終端機所使用的環境中，設定自行託管的 URL 與專案。當缺少憑證時，CLI 會自動探索執行個體政策：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

在確實缺少憑證的情況下，活動記錄與 XCResult 套件會在本地解析，並以結構化報告的形式傳送。不會提交原始封存檔、附件、涵蓋率/歷史記錄上傳、遠端處理器、分片參考或選擇性執行的證據。報告仍可檢視，但無法更新已認證的測試案例狀態，也無法觸發隔離或失敗自動化流程。儀表板與其他需要特權的指令仍須登入。除非執行個體另行啟用網路信任的快取存取，或已提供憑證，否則請保持快取整合為停用狀態。

現有的憑證仍維持已認證狀態。無效、損毀、空白或被拒絕更新的憑證會以安全方式失敗並保留在磁碟上，因此後續指令不會在未經簽署的情況下靜默執行。請重新登入或明確登出，作為刻意的恢復動作。在升級免憑證用戶端之前，請將所有伺服器複本升級至支援探索功能的版本，並將最終伺服器 URL 設定為不含重新導向。不具備探索功能的舊版伺服器、已停用的執行個體，以及探索失敗的情況，仍需要驗證。無需進行用戶端選擇加入。請獨立設定 `TUIST_ACTOR_ID=""` 以省略已設定的參與者聲明；經驗證的憑證身分不受影響。
