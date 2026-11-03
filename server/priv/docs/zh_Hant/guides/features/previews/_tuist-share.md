## 使用 tuist share 的追蹤頻道 {#share-tracks}

對於使用 `tuist share` 發布的工作流程，請使用 `--track` 來選擇追蹤頻道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 版本資訊 {#release-notes}

使用追蹤頻道來區分環境群組，並為個別建置提供版本資訊：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你的應用程式名稱、應用程式檔案路徑，或可執行檔分發及其 `--executable` 選項。版本資訊為選填的純文字，最多 10,000 個字元。第一行非空白內容會以單行摘要的形式出現在預覽清單中，讓建置編號與其他識別資訊一目了然。過長的行會被截斷；完整資訊則顯示在詳細頁面。搜尋結果會比對顯示名稱與完整的版本資訊，包含未在摘要中顯示的行。支援多行版本資訊，例如 `--release-notes "$(< release-notes.txt)"`。這不會改變應用程式的顯示名稱或其追蹤頻道。

### 相容性 {#preview-metadata-compatibility}

版本資訊是附加的中繼資料，不屬於預覽的身分識別。來自新舊客戶端的上傳仍會在跨平台時歸類到同一個預覽。系統會保留第一行非空白的版本資訊：後續上傳可以補充先前缺少的資訊，但無法覆寫現有的版本資訊。省略 `release_notes`、傳送 `null`，或傳送空字串或僅含空白的字串，都不會清除版本資訊。現有的預覽不會回溯填充，且在沒有版本資訊的情況下仍然有效。

清單 API 的選填查詢參數 `track` 會以不分大小寫的方式比對完整的追蹤頻道名稱，與現有的追蹤頻道儲存方式一致。省略此參數或傳送空值（`?track=`）即可列出所有追蹤頻道。追蹤頻道名稱仍為開放字串，而非固定的值列表。`GET /api/projects/:account_handle/:project_handle/previews/tracks` 會回傳 `{total_count, tracks: [{name, count}]}`，其中包含已排序且不分大小寫分組的具名追蹤頻道，其授權範圍與列出示建置之預覽讀取權限相同。計數涵蓋整個專案，不受分頁、搜尋及所選追蹤頻道的影響；總數包含未追蹤的預覽。僅計入具有 bundle identifier 且可列出的預覽。清單 API 也接受選填的 `search`，用於對顯示名稱或完整版本資訊進行不分大小寫的字串比對，並在分頁前與追蹤頻道條件合併套用。現有的 `display_name` 篩選仍維持精確比對。

舊版客戶端可以繼續上傳與列出預覽，無需傳送這兩個欄位。新版客戶端能接受省略追蹤頻道或版本資訊的舊版回應，並忽略未來伺服器新增的未知回應屬性。API 整合也應忽略未知的回應屬性，以確保附加中繼資料的相容性。

自行託管的部署需要支援版本資訊與追蹤頻道篩選的伺服器版本，以及更新後的客戶端，才能使用這些功能。較舊的伺服器可能會忽略版本資訊或未知的查詢參數。

## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **必須與 Git 平台整合**
>
> 若要自動取得 Pull/Merge Request 評論，請將你的 <.localized_link href="/guides/server/accounts-and-projects">遠端專案</.localized_link> 與 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 整合。

當你的 Tuist 專案與 Git 平台連接後，請在 CI 中成功建置應用程式後加入 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接在你的 Pull/Merge Request 中張貼預覽連結，讓審查者無需在本機建置即可測試：

![含有 Tuist Preview 連結的 GitHub App 評論](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 取得 JSON 輸出：

```bash
tuist share --json
```

利用結果進行自訂自動化，例如從 CI 張貼 Slack 訊息。`url` 鍵包含完整的預覽連結；`qrCodeURL` 指向用於在裝置上開啟預覽的 QR Code 圖片：

```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
