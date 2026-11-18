---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 代管平台 | 整合 | 指南 | Tuist",
  "description": "在 Entire Trails 上發布 Tuist 建置、測試、套件與預覽的洞察。"
}
---
# Entire 整合 {#entire}

Tuist 會在每個已連結儲存庫的開啟或草稿 [Trail](https://docs.entire.com/guides/trails/overview) 上維護一篇摘要討論。摘要包含可用的建置結果、測試失敗與不穩定測試、套件大小，以及應用程式預覽，並提供指向 Tuist 完整報告的連結。

> [!IMPORTANT]
> **早期存取**
>
> Entire 外掛程式需要合作夥伴註冊，其 Trail 討論與 webhook 合約仍屬實驗性質。你的 Tuist 管理員可以為所有帳戶或選定帳戶啟用此整合。你的 Entire 專案也必須被允許安裝已註冊的外掛程式。

## 設定 {#setup}

安裝流程與 GitHub 整合相同：先為你的帳戶安裝外掛程式，再將儲存庫連結至 Tuist 專案。在託管式 Tuist 上，你的管理員會處理外掛程式註冊與伺服器設定；你只需執行下列步驟。

1. 開啟你帳戶的 **設定 → 整合**。
2. 在 **Entire** 中，選擇 **安裝 Entire 外掛程式**。選擇你想要與 Tuist 共用的 Entire 專案與儲存庫。

   ![從帳戶整合安裝 Entire 外掛程式](/images/guides/integrations/gitforge/entire/integrations.png)

3. 回到 Tuist，選擇 **新增專案連線**。在 **選擇要連結的儲存庫** 中，選擇你的 Tuist 專案與 Entire 儲存庫，然後選擇 **建立連線**。如果只有一個可用的 Tuist 專案，系統會自動選取。

   ![將 Tuist 專案連結至 Entire 儲存庫](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 繼續使用現有的已驗證 Tuist 指令，從 CI 上傳你的洞察資料。Tuist 會將其比對至每個 Trail 的目前提交 SHA；不需要使用 Entire 專屬的 CLI 旗標。

Tuist 專案可以在保留 GitHub 連線的同時，也將摘要發布至 Entire。這對於 GitHub 鏡像很有用。Trail 摘要不需要 Tuist 的 CI 執行器，也不會變更你現有的 CI 供應商。

隨著洞察資料抵達，Tuist 會更新同一篇討論。開啟或重新開啟 Trail 時，也會擷取其 head 提交先前上傳的洞察資料。已關閉與已合併的 Trail 不會更新。較舊提交的結果絕不會作為當前 head 的結果呈現。如果目前提交沒有洞察資料，Tuist 會保持既有摘要不變；每筆結果都會包含其提交雜湊。

若要移除專案連線，請開啟其 **管理** 選單並選擇 **移除連線**，做法與 GitHub 相同。這會停止未來的更新，並刪除 Tuist 的本機討論指標。已發布的留言仍會保留在 Entire 上。重新連線可在摘要仍可存取時恢復既有摘要。若要變更外掛程式的儲存庫存取權或解除安裝，請使用 Entire 中專案的 **外掛程式** 設定。

## 伺服器設定 {#server-configuration}

本節適用於 Tuist 伺服器營運者。請使用 [外掛程式註冊指南](https://docs.entire.com/guides/api/plugins/register) 向 Entire 註冊外掛程式。請求 `contents:read` 與 `discussions:write`。讀取權限用於 Trail 事件與討論探索；不需要儲存庫寫入權限。

設定以下伺服器環境變數：

| 變數 | 用途 |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | 由 Entire 確認的 Slug |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | PEM 格式的 Ed25519 私鑰，透過你的秘密儲存區提供 |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | 使用基於 JWKS 的金鑰註冊時的金鑰 ID；否則為選填 |
| `TUIST_ENTIRE_CORE_URL` | 用於安裝請求的 Entire Core；預設為 `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | 註冊時由 Entire 提供的 webhook 簽署金鑰 URL |

對於受管的 Helm 部署，將私鑰 PEM 儲存在環境的 1Password 保險庫中，項目名稱為 `ENTIRE_PLUGIN/private_key`，然後同時啟用 `server.config.entirePluginKey.enabled` 與 `server.config.managedSecrets`。External Secrets 會透過現有的 server-config Secret 提供 `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY`，且不會截斷多行 PEM。項目與欄位名稱可透過 `server.config.entirePluginKey.item` 與 `.field` 進行設定。此映射預設為關閉，且不會設定 slug 或 webhook 簽署金鑰 URL；請在註冊後分別提供這些資訊。每個環境應使用各自的簽署金鑰。僅與 Entire 分享公開 PEM，切勿分享私鑰。

註冊 `https://<your-tuist-host>/integrations/entire/callback` 作為安裝後回呼 URL，並註冊 `https://<your-tuist-host>/webhooks/entire` 作為 webhook URL。套用伺服器遷移後，全域啟用 `entire_trails` 功能旗標以向所有帳戶提供此整合，或為選定帳戶啟用。若要公開推出，請聯絡你的 Entire 窗口，允許在擁有該外掛程式的專案之外進行安裝；啟用 Tuist 功能旗標不會改變 Entire 的安裝政策。Entire Trail 摘要獨立於 Tuist 的 CI 執行設定與功能旗標。

Tuist 會驗證安裝收據與 webhook 簽章，發行短效且限定儲存庫範圍的權杖，並在發布前探索每個儲存庫目前的處理區域。權杖絕不會嵌入報告連結中。
