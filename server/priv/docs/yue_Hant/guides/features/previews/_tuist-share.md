## 使用 tuist share 嘅追蹤頻道 {#share-tracks}

對於使用 `tuist share` 發佈嘅工作流程，請使用 `--track` 選擇追蹤頻道：

```bash
tuist share App --track beta
tuist share App --track nightly
```

## 版本說明 {#release-notes}

為個別構建使用追蹤頻道來分組環境，並使用版本說明：

```bash
tuist share App --track QA --release-notes "Fix sign-in and improve the checkout flow"
```

將 `App` 替換為你嘅應用程式名稱、應用程式檔案路徑或可執行分發及其 `--executable` 選項。版本說明係選用嘅純文字，最多 10,000 個字符。第一行非空白行會以單行摘要形式出現喺預覽列表中，因此構建編號同其他識別資訊可以一目了然。長行會被截斷；完整說明會顯示喺詳細頁面。搜尋結果會匹配顯示名稱同完整版本說明，包括摘要中未顯示嘅行。支援多行說明，例如 `--release-notes "$(< release-notes.txt)"`。佢哋不會更改應用程式嘅顯示名稱或其追蹤頻道。

### 兼容性 {#preview-metadata-compatibility}

版本說明不會更改構建所屬嘅預覽。預覽收到嘅第一組說明會被保留：後續上傳可以為沒有說明嘅預覽添加說明，但不能覆蓋或清除現有說明。喺版本說明功能存在之前上傳嘅預覽仍然有效，無需說明。

自託管部署需要支援版本說明同追蹤頻道過濾嘅伺服器版本，以及更新咗嘅客戶端。較舊嘅伺服器會忽略說明。有關列表端點嘅追蹤頻道同搜尋過濾器，請參閱 [API 參考](https://tuist.dev/api/docs)。

## 拉取/合併請求評論 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git 平台整合**
>
> 要獲取自動拉取/合併請求評論，請將你嘅 <.localized_link href="/guides/server/accounts-and-projects">遠程項目</.localized_link> 與 Git 平台整合：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。

一旦你嘅 Tuist 項目與你嘅 Git 平台連接，請喺 CI 中成功構建應用程式後添加 <.localized_link href="/cli/share">`tuist share`</.localized_link>。Tuist 會直接喺你嘅拉取/合併請求中發佈預覽連結，以便審查者無需本地構建即可測試：

![帶有 Tuist 預覽連結嘅 GitHub 應用程式評論](/images/guides/features/github-app-with-preview.png)

## 自動化 {#automations}

使用 `--json` 從 `tuist share` 獲取 JSON 輸出：

```bash
tuist share --json
```

使用結果進行自定義自動化，例如從 CI 發佈 Slack 消息。`url` 鍵包含完整預覽連結；`qrCodeURL` 指向用於喺設備上打開預覽嘅 QR 碼圖像：

```json
{
  "id": 1234567890,
  "url": "https://tuist.dev/preview/1234567890",
  "qrCodeURL": "https://tuist.dev/preview/1234567890/qr-code.svg"
}
```
