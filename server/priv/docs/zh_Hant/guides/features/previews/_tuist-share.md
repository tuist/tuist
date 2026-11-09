## 使用 tuist share 的追蹤頻道 {#share-tracks}

對於使用 `tuist share` 發布的工作流程，請使用 `--track` 來選擇追蹤頻道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 版本說明 {#release-notes}

使用追蹤頻道區分環境群組，並為個別建置提供版本說明：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你的應用程式名稱、應用程式檔案路徑或可執行檔分發及其 `--executable` 選項。版本說明為選填的純文字，最多 10,000 個字元。第一個非空白行會以單行摘要的形式出現在預覽清單中，讓建置編號與其他識別資訊一目了然。過長的行會被截斷；完整說明則顯示在詳細頁面。搜尋結果會比對顯示名稱與完整版本說明，包括未在摘要中顯示的行。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。它們不會改變應用程式的顯示名稱或其追蹤頻道。

### 相容性 {#preview-metadata-compatibility}

版本說明不會改變建置所屬的預覽。預覽收到的第一份說明會被保留：後續上傳可以為沒有說明的預覽新增說明，但無法覆寫或清除現有的說明。在版本說明功能推出之前上傳的預覽，即使沒有說明仍然有效。

自行託管的部署需要支援版本說明與追蹤頻道篩選的伺服器版本，以及更新後的用戶端。較舊的伺服器會忽略這些說明。關於列表端點的追蹤頻道與搜尋篩選器，請參閱 [API 參考文件](https://tuist.dev/api/docs)。

## Pull/Merge Request 留言 {#pullmerge-request-comments}

> [!WARNING]
> **需要整合 Git Forge**
>
> 若要自動在 Pull/Merge Request 中留言，請將你的 <.localized_link href="/guides/server/accounts-and-projects">遠端專案</.localized_link> 與 <.localized_link href="/guides/integrations/gitforge/github">Git Forge</.localized_link> 整合。

當你的 Tuist 專案與 Git 平台連接後，請在 CI 中成功建置應用程式後加入 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接在您的 Pull/Merge Request 中張貼預覽連結，讓審查者無需在本機建置即可測試：

![包含 Tuist Preview 連結的 GitHub App 留言](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 取得 JSON 輸出：

```bash
tuist share --json
```

利用結果進行自訂自動化，例如從 CI 發送 Slack 訊息。`url` 鍵包含完整的預覽連結；`qrCodeURL` 指向用於在裝置上開啟預覽的 QR Code 圖片：

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
