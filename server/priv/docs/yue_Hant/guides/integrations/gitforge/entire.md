---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "喺 Entire Trails 發布 Tuist 構建、測試、捆綁同預覽洞察。"
}
---
# Entire 整合 {#entire}

Tuist 會為每個已連接儲存庫的開放或草稿 [Trail](https://docs.entire.com/guides/trails/overview) 維護一個摘要討論。摘要包括可用的構建結果、測試失敗和不穩定測試、套件大小，以及應用程式預覽，並附有指向 Tuist 上完整報告的連結。

> [!IMPORTANT]
> **早期存取**
>
> Entire 外掛程式需要合作夥伴註冊，其 Trail 討論和 webhook 合約均屬實驗性質。你的 Tuist 管理員可以為所有帳戶或選定帳戶啟用此整合。你的 Entire 專案也必須獲准安裝已註冊的外掛程式。

## 設定 {#setup}

安裝流程與 GitHub 整合相同：先為你的帳戶安裝外掛程式，然後將儲存庫連接到 Tuist 專案。在託管式 Tuist 上，你的管理員會處理外掛程式註冊和伺服器設定；你只需執行以下步驟。

1. 開啟你帳戶的 **設定 → 整合**。
2. 在 **Entire** 中，選擇 **安裝 Entire 外掛程式**。選擇你想與 Tuist 共享的 Entire 專案和儲存庫。

   ![從帳戶整合安裝 Entire 外掛程式](/images/guides/integrations/gitforge/entire/integrations.png)

3. 返回 Tuist，選擇 **新增專案連線**。在 **選擇要連接的儲存庫** 中，選擇你的 Tuist 專案和 Entire 儲存庫，然後選擇 **建立連線**。如果只有一個 Tuist 專案可用，它會被自動選取。

   ![將 Tuist 專案連接到 Entire 儲存庫](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 繼續使用你現有的已驗證 Tuist 命令從 CI 上傳洞察數據。Tuist 會將它們與每個 Trail 的當前 commit SHA 匹配；不需要任何 Entire 專屬的 CLI 標誌。

Tuist 專案可以保留其 GitHub 連線，同時將摘要發布到 Entire。這對於 GitHub 鏡像很有用。Trail 摘要不需要 Tuist 的 CI 執行器，也不會改變你現有的 CI 供應商。

隨著洞察數據到達，Tuist 會更新同一個討論。開啟或重新開啟 Trail 也會獲取其頭部 commit 之前上傳的洞察數據。已關閉和已合併的 Trail 不會更新。來自較舊 commit 的結果絕不會作為當前頭部的結果呈現。如果當前 commit 沒有洞察數據，Tuist 會保持任何現有摘要不變；每個結果都包含其 commit 哈希值。

要移除專案連線，請開啟其 **管理** 選單並選擇 **移除連線**，就像對 GitHub 所做的一樣。這會停止未來的更新並刪除 Tuist 的本地討論指標。已發布的評論仍保留在 Entire 上。重新連線會在摘要仍可訪問時恢復現有摘要。要更改外掛程式的儲存庫訪問權限或卸載它，請使用 Entire 中專案的 **外掛程式** 設定。

## 伺服器設定 {#server-configuration}

本節適用於 Tuist 伺服器營運者。使用 [外掛程式註冊指南](https://docs.entire.com/guides/api/plugins/register) 向 Entire 註冊外掛程式。請求 `contents:read` 和 `discussions:write`。讀取權限是 Trail 事件和討論發現所必需的；不需要儲存庫寫入訪問權限。

設定這些伺服器環境變數：

| 變數 | 用途 |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 確認的 Slug |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | PEM 格式的 Ed25519 私鑰，透過你的秘密儲存庫提供 |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 使用基於 JWKS 的金鑰註冊時的 Key ID；否則為可選 |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求的 Entire Core；預設為 `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 由 Entire 在註冊時提供的 Webhook 簽名金鑰 URL |

對於受管理的 Helm 部署，將私有 PEM 儲存在環境的 1Password 保險庫中作為 `ENTIRE_PLUGIN/private_key`，然後與 `server.config.managedSecrets` 一起啟用 `server.config.entirePluginKey.enabled`。External Secrets 透過現有的 server-config Secret 提供 `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY`，而不裁剪多行 PEM。項目和欄位名稱可透過 `server.config.entirePluginKey.item` 和 `.field` 進行配置。此映射預設為關閉，且不配置 slug 或 webhook 簽名金鑰 URL；請在註冊後單獨提供這些內容。每個環境應使用其自己的簽名金鑰。僅與 Entire 共享公開 PEM，切勿共享私鑰。

註冊 `https://<your-tuist-host>/integrations/entire/callback` 作為安裝後 URL，並註冊 `https://<your-tuist-host>/webhooks/entire` 作為 webhook URL。應用伺服器遷移後，全局啟用 `entire_trails` 功能標誌以向所有帳戶提供整合，或為選定帳戶啟用它。對於公開推出，請聯絡你的 Entire 聯繫人以允許在外掛程式擁有專案之外進行安裝；啟用 Tuist 功能標誌不會改變 Entire 的安裝策略。Entire Trail 摘要獨立於 Tuist 的 CI 執行配置和功能標誌。

Tuist 會驗證安裝收據和 webhook 簽名，鑄造短生命週期的儲存庫範圍令牌，並在發布前發現每個儲存庫的當前處理區域。令牌絕不會嵌入報告連結中。
