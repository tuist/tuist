## 使用 tuist share 追蹤版本 {#share-tracks}

若工作流程使用 `tuist share` 發布，請使用 `--track` 選擇追蹤版本：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 發行說明 {#release-notes}

使用追蹤版本區分環境群組，並為個別建置提供發行說明：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你的應用程式名稱、應用程式檔案路徑或可執行檔散發套件及其 `--executable` 選項。發行說明為選填的純文字，最多 10,000 個字元。第一行非空白內容會在預覽清單中以單行摘要顯示，讓建置編號與其他識別資訊一目了然。過長的行會被截斷；完整說明會顯示在詳細頁面。搜尋結果會比對顯示名稱與完整發行說明，包含未在摘要中顯示的行。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。這不會改變應用程式的顯示名稱或其追蹤版本。

### 相容性 {#preview-metadata-compatibility}

發行說明不會改變建置所屬的預覽。預覽接收的第一筆說明會被保留：後續上傳可以為尚未有說明的預覽新增說明，但無法覆寫或清除既有說明。在發行說明功能推出前上傳的預覽仍然有效，不需補充說明。

自行託管的部署需要支援發行說明與追蹤版本篩選的伺服器版本，以及更新後的用戶端。較舊的伺服器會忽略這些說明。關於清單端點的追蹤版本與搜尋篩選器，請參閱 [API 參考文件](https://tuist.dev/api/docs)。

## Pull/Merge Request 留言 {#pullmerge-request-comments}

> [!WARNING]
> **需要整合 Git 平台**
>
> 若要自動在 Pull/Merge Request 中留下留言，請將你的 <.localized_link href="/guides/server/accounts-and-projects">遠端專案</.localized_link> 與 Git 平台整合：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。

當你的 Tuist 專案與 Git 平台連接後，在 CI 成功建置應用程式後加入 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接在 Pull/Merge Request 中張貼預覽連結，讓審查者無需在本機建置即可測試：

![包含 Tuist Preview 連結的 GitHub App 留言](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 取得 JSON 輸出：

```bash
tuist share --json
```

將結果用於自訂自動化流程，例如從 CI 發送 Slack 訊息。`url` 鍵包含完整的預覽連結；`qrCodeURL` 指向 QR Code 圖片，可在裝置上開啟預覽：

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
