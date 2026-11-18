## 使用 tuist share 嘅軌道 {#share-tracks}

對於使用 `tuist share` 發布嘅工作流程，請使用 `--track` 來選擇軌道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 版本說明 {#release-notes}

使用軌道來分組環境，並為個別構建添加版本說明：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你嘅應用程式名稱、應用程式檔案路徑或可執行分發及其 `--executable` 選項。版本說明係可選嘅純文字，最多 10,000 個字符。第一行非空白行會以單行摘要形式顯示喺預覽列表中，因此構建編號同其他識別資訊可以一目了然。長行會被截斷；完整說明會顯示喺詳情頁面。搜尋結果會匹配顯示名稱同完整版本說明，包括未喺摘要中顯示嘅行。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。佢哋唔會改變應用程式嘅顯示名稱或其軌道。

### 相容性 {#preview-metadata-compatibility}

版本說明唔會改變構建所屬嘅預覽。預覽收到嘅第一份說明會被保留：後續上傳可以為冇說明嘅預覽添加說明，但唔能覆蓋或清除現有說明。喺版本說明功能存在之前上傳嘅預覽仍然有效，無需說明。

自託管部署需要支援版本說明同軌道過濾嘅伺服器版本，以及更新後嘅客戶端。較舊嘅伺服器會忽略說明。有關列表端點嘅軌道同搜尋過濾器，請參閱 [API 參考](https://tuist.dev/api/docs)。

## Pull/Merge Request 評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git Forge 整合**
>
> 要獲取自動嘅 Pull/Merge Request 評論，請將你嘅 <.localized_link href="/guides/server/accounts-and-projects">遠端項目</.localized_link> 與 <.localized_link href="/guides/integrations/gitforge/github">Git Forge</.localized_link> 整合。

一旦你嘅 Tuist 項目與你嘅 Git 平台連接，請喺 CI 中成功構建應用程式後添加 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接喺你嘅 Pull/Merge Request 中發布預覽連結，以便審查者無需本地構建即可測試：

![帶有 Tuist Preview 連結嘅 GitHub App 評論](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 獲取 JSON 輸出：

```bash
tuist share --json
```

使用結果進行自定義自動化，例如從 CI 發布 Slack 消息。`url` 鍵包含完整嘅預覽連結；`qrCodeURL` 指向用於喺設備上打開預覽嘅 QR Code 圖片：

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
