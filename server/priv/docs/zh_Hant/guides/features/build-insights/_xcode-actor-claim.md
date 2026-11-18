## 回報行為者宣告 {#report-actor-claim}

只有在您將 `TUIST_ACTOR_ID` 明確設為組織範圍的標籤（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`）時，建立回報的請求才會包含可選的 `x-tuist-actor-id` 標頭。預設不會傳送任何標籤，且 Tuist 不會偵測作業系統的使用者名稱。空的 `TUIST_ACTOR_ID` 會省略所回報的識別碼，但不會移除基於憑證的已驗證身分。識別碼必須是 1–128 位元組的非空白可列印 ASCII 字元；無效的覆寫值會被省略，且不會回退至其他值。如果自訂代理伺服器拒絕不熟悉的標頭，請使用空白的環境變數覆寫來選擇退出。

已驗證的個人憑證具有優先權；否則，用戶端回報的識別碼會顯示為 **未驗證**，且永遠不會授予權限或自動連結至使用者。任何能檢視專案回報的人都能看到這些識別碼，包括專案公開時的公眾檢視者，並且它們也會包含在資料匯出中，因此請勿包含機密資訊。這適用於建置、測試和命令事件回報。舊版伺服器會忽略此可選標頭，而新版伺服器則接受沒有此標頭的舊版用戶端。沒有識別碼的新共用權杖回報會顯示 **未知**，而非發布組織；歷史回報則保留其先前的歸屬。建置和測試清單會區分已驗證的使用者與未驗證的回報識別碼。除非自託管執行個體明確啟用免憑證回報，且用戶端發現該政策，否則仍需要進行身分驗證。

### Scheme 後置動作 {#actor-claim-post-actions}

行為者宣告預設為停用狀態。若要為 Scheme 後置動作設定宣告，請在該腳本中設定 `TUIST_ACTOR_ID`，而不是依賴 Shell 匯出的變數。從 Dock 啟動的 Xcode 不會繼承 `~/.zshrc` 中的變數。若要使用 Homebrew 明確抑制已設定的宣告，請使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 時，在 Mise 載入其環境後覆寫該值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用明確的標籤而非空值來選擇加入。
