## 使用 tuist share 的軌道 {#share-tracks}

對於使用 `tuist share` 發布的工作流程，請使用 `--track` 來選擇軌道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 版本說明 {#release-notes}

為個別建置用途使用軌道進行環境分組，並使用版本說明：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你的應用程式名稱、應用程式檔案路徑或可執行檔發行版及其 `--executable` 選項。版本說明為選填的純文字，最多 10,000 個字元。第一行非空白行會以單行摘要的形式出現在預覽清單中，因此建置編號和其他識別資訊可一目瞭然。過長的行會被截斷；完整說明會顯示在詳細頁面上。搜尋結果會比對顯示名稱和完整版本說明，包括未在摘要中顯示的行。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。它們不會變更應用程式的顯示名稱或其軌道。

### 相容性 {#preview-metadata-compatibility}

版本說明不會改變建置所屬的預覽。預覽收到的第一份說明會被保留：後續上傳可以為沒有說明的預覽新增說明，但無法覆寫或清除現有的說明。在版本說明功能推出之前上傳的預覽，即使沒有說明仍然有效。

自行託管的部署需要支援版本說明和軌道篩選的伺服器版本，以及更新後的用戶端。較舊的伺服器會忽略這些說明。如需清單端點的軌道和搜尋篩選器，請參閱 [API 參考文件](https://tuist.dev/api/docs)。

## 拉取請求／合併請求留言 {#pullmerge-request-comments}

> [!WARNING]
> **需要整合 Git 平台**
>
> 若要取得自動化的拉取請求／合併請求留言，請將你的 <.localized_link href="/guides/server/accounts-and-projects">遠端專案</.localized_link> 與 Git 平台整合：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。

當你的 Tuist 專案與 Git 平台連接後，請在 CI 中成功建置應用程式後加入 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接在拉取請求／合併請求中張貼預覽連結，讓審查者無需在本機建置即可測試：

![包含 Tuist Preview 連結的 GitHub App 留言](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 取得 JSON 輸出：

```bash
tuist share --json
```

將結果用於自訂自動化，例如從 CI 發佈 Slack 訊息。`url` 鍵包含完整的預覽連結；`qrCodeURL` 指向 QR Code 圖片，用於在裝置上開啟預覽：

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
