## 使用 tuist share 嘅頻道 {#share-tracks}

對於使用 `tuist share` 發佈嘅工作流程，請使用 `--track` 選擇一個頻道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 版本說明 {#release-notes}

為個別構建用途，使用頻道劃分環境組別並加入版本說明：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你嘅應用程式名稱、應用程式檔案路徑或可執行分發套件，連同其 `--executable` 選項。版本說明係選用嘅純文字，最多 10,000 個字元。第一行非空白內容會以單行摘要形式出現喺預覽列表中，令到構建編號同其他識別資訊一目了然。過長嘅行會被截斷；完整說明會顯示喺詳情頁面。搜尋結果會匹配顯示名稱同完整版本說明，包括未喺摘要中顯示嘅行數。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。呢啲說明唔會改變應用程式嘅顯示名稱或其頻道。

### 兼容性 {#preview-metadata-compatibility}

版本說明係附加元數據，唔屬於預覽身份嘅一部分。來自新舊客戶端嘅上傳仍然會歸類到跨平台嘅同一個預覽中。系統會保留第一行非空白說明：後續上傳可以補充之前缺失嘅說明，但無法覆蓋現有說明。省略 `release_notes`、發送 `null`，或者發送空字符串或僅含空白字符嘅字符串，永遠唔會清除說明。現有預覽唔會回溯填充，即使沒有說明仍然有效。

列表 API 嘅選用 `track` 查詢參數會不區分大小寫地匹配整個頻道名稱，與現有頻道存儲保持一致。省略該參數或發送空值（`?track=`）以列出所有頻道。頻道名稱保持為開放字符串，而非固定值列表。`GET /api/projects/:account_handle/:project_handle/previews/tracks` 返回 `{total_count, tracks: [{name, count}]}`，包含按名稱排序且不區分大小寫分組嘅頻道，享有與列出構建相同嘅預覽讀取授權。計數涵蓋整個項目，獨立於分頁、搜尋和所選頻道；總數包括未追蹤嘅預覽。只有可列出且帶有 bundle identifier 嘅預覽才會被計入。列表 API 亦接受選用嘅 `search`，用於對顯示名稱或完整版本說明進行不區分大小寫嘅字面子串匹配，並喺分頁前與頻道條件組合。現有嘅 `display_name` 過濾仍然保持精確匹配。

舊版客戶端可以繼續上傳和列出預覽，無需發送任一字段。新版客戶端接受省略頻道或說明嘅舊版響應，並忽略未來服務器添加嘅未知響應屬性。API 集成同樣應該忽略未知響應屬性，以保持附加元數據嘅兼容性。

自託管部署需要支持版本說明和頻道過濾嘅服務器版本，以及更新後嘅客戶端，才能使用這些功能。較舊嘅服務器可能會忽略說明或未知查詢參數。

## 拉取/合併請求評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要與 Git 平台集成**
>
> 要獲取自動嘅拉取/合併請求評論，請將你嘅 <.localized_link href="/guides/server/accounts-and-projects">遠程項目</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。

一旦你嘅 Tuist 項目與 Git 平台連接，請喺 CI 中成功構建應用程式後添加 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接喺你嘅拉取/合併請求中發布預覽鏈接，讓審查者無需本地構建即可測試：

![帶有 Tuist Preview 鏈接嘅 GitHub 應用評論](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 獲取 JSON 輸出：

```bash
tuist share --json
```

使用結果進行自定義自動化，例如從 CI 發布 Slack 消息。`url` 鍵包含完整嘅預覽鏈接；`qrCodeURL` 指向用於喺設備上打開預覽嘅 QR code 圖片：

```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
