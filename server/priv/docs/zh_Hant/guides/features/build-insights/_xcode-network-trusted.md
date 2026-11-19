## 在私有網路上進行免憑證回報 {#network-trusted-publishing}

自行託管部署可讓開發人員無需登入即可發布已完成的報告。營運人員必須在執行個體上設定 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true`，並依照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自行託管指南</.localized_link> 所述重新啟動。此設定適用於所有支援的專案；儀表板中沒有相關設定。請在 scheme 後置動作或終端機使用的環境中，設定自行託管的 URL 與專案。當缺少憑證時，CLI 會自動探索執行個體政策：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

在確實缺少憑證的情況下，活動記錄與 XCResult 套件會在本地解析，並以結構化報告的形式傳送。不會提交原始封存檔、附件、涵蓋率／歷史記錄上傳、遠端處理器、分片參考，或選擇性執行的證據。報告仍可見，但無法更新已認證的測試案例狀態，也無法觸發隔離或失敗自動化流程。儀表板與其他需要權限的命令仍需登入。除非執行個體另行啟用網路信任的快取存取，或已提供憑證，否則請保持快取整合停用。

現有憑證仍維持已認證狀態。無效、損毀、空白或被拒絕更新的憑證會以安全方式失敗並保留在磁碟上，因此後續命令不會在未經簽署的情況下靜默執行。請重新登入，或明確登出作為刻意的復原動作。在升級免憑證用戶端之前，請將所有伺服器複本升級至支援探索功能的版本，並設定最終伺服器 URL，避免重新導向。不支援探索功能的舊版伺服器、已停用的執行個體，以及探索失敗的情況，仍需要驗證。不需要用戶端選擇加入。請獨立設定 `TUIST_ACTOR_ID=""` 以省略設定的參與者聲明；已驗證的憑證身分不受影響。
