## 報告參與者聲明 {#report-actor-claim}

只有當你明確將 `TUIST_ACTOR_ID` 設定為組織範圍的標籤（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`）時，建立報告的請求才會包含可選的 `x-tuist-actor-id` 標頭。預設不會傳送任何標籤，而 Tuist 亦不會偵測作業系統的使用者名稱。空的 `TUIST_ACTOR_ID` 會省略所報告的識別碼，但不會移除基於憑證的已驗證身份。識別碼必須為 1–128 位元組的非空格可列印 ASCII 字元；無效的覆寫會被省略，且不會回退。如果自訂代理伺服器拒絕不熟悉的標頭，請使用空的环境變數覆寫來選擇退出。

已驗證的個人憑證具有優先權；否則，客戶端報告的識別碼會顯示為 **未經驗證**，且絕不會授予權限或自動連結至使用者。任何可以檢視專案報告的人都能看到這些識別碼，包括當專案公開時的公眾檢視者，並且它們會包含在資料匯出中，因此請勿包含機密資訊。這適用於建置、測試及命令事件報告。舊版伺服器會忽略此可選標頭，而新版伺服器則接受沒有此標頭的舊版客戶端。沒有識別碼的新共用令牌報告會顯示 **未知**，而非發布組織；歷史報告則保留其先前的歸屬。建置和測試清單會區分已驗證使用者與未經驗證的報告識別碼。除非自託管實例明確啟用免憑證報告，且客戶端發現該政策，否則仍需要進行身份驗證。

### Scheme 後續動作 {#actor-claim-post-actions}

參與者聲明預設為停用狀態。若要為 scheme 後續動作進行設定，請在該腳本中設定 `TUIST_ACTOR_ID`，而不要依賴 shell 匯出變數。從 Dock 啟動的 Xcode 不會繼承 `~/.zshrc` 中的變數。若要使用 Homebrew 明確抑制已設定的聲明，請使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 時，請在 Mise 載入其環境後覆寫該值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

請使用明確的標籤而非空值來選擇加入。
