---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "喺 Entire Trails 上發布 Tuist 嘅構建、測試、捆綁同預覽洞察。"
}
---
# Entire 整合 {#entire}

Tuist 可以將構建、測試、預覽和捆綁包的洞察發佈到 [Entire](https://entire.com) 儲存庫中處於開啟或草稿狀態的 [Trails](https://docs.entire.com/guides/trails/overview)。每個 Trail 都會獲得一個 Tuist 閘門，其中包含運行報告、針對失敗和不穩定測試的全量變更發現項，以及一條摘要評論；Tuist 會在新洞察到達時更新該評論，而不是每次上傳都發佈新評論。

安裝外掛程式不會執行構建或測試。你現有的工作流程會繼續將結果上傳至 Tuist，而此整合會將這些結果帶入你的 Trails。

## 設定 {#setup}

Tuist 帳戶的管理員會先安裝外掛程式，然後將儲存庫連接至 Tuist 專案，做法與 <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> 和 <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> 整合相同。

1. 開啟你帳戶的 **Settings → Integrations**。
2. 在 Entire 卡片中，選擇 **Install Entire plugin**。選擇你想要與 Tuist 共享的 Entire 專案和儲存庫。

   ![從帳戶整合安裝 Entire 外掛程式](/images/guides/integrations/gitforge/entire/integrations.png)

3. 返回 Tuist，選擇 **Add new project connection**。在 **Choose repository to connect to** 中，選擇你的 Tuist 專案和 Entire 儲存庫，然後選擇 **Create Connection**。如果只有一個可用的 Tuist 專案，它會被自動選中。

   ![將 Tuist 專案連接至 Entire 儲存庫](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 继续使用你现有的、已认证的 Tuist 命令从 CI 上传结果，例如使用 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。Tuist 会将结果匹配到每个 Trail 的当前头部提交，因此不需要特定于 Entire 的标志。

Tuist 專案可以在保持其 GitHub 連接的同時也將內容發佈到 Entire，這在 Entire 儲存庫鏡像 GitHub 儲存庫時很有用。此整合不需要 Tuist 的 CI 執行器，也不會改變你的 CI 供應商。

## 報告與權限 {#reports-and-permissions}

安裝外掛程式時，你會授予它查找 Trails 和發佈報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| 儲存庫內容：讀取 | 接收 Trail 事件，並查找帶有頭部提交的開啟和草稿 Trails。 |
| 檢查：寫入 | 在 Trail 的頭部提交上發佈 Tuist 閘門。 |
| 發現項：寫入 | 將失敗和不穩定測試作為發現項發佈，並解決被較新報告取代的發現項。 |
| 討論：寫入 | 發佈並更新摘要評論。即使沒有此權限，Tuist 仍會發佈閘門和發現項。 |

Tuist 不需要對你的原始碼具有寫入權限，也不需要合併 Trails 的權限。

Tuist 會在每個 Trail 上發佈三樣東西：

- **閘門：** Tuist 檢查會出現在 **Gates** 下方，附帶運行報告和指向 Tuist 上專案的連結。它列在 Tuist 外掛程式下，與 GitHub 鏡像的 **Checks** 閘門分開。它以 `neutral` 結論完成，Entire 將其顯示為通過，因為上傳的結果不會告訴 Tuist 每個預期的 CI 作業是否已完成。即使存在發現項，它也不會阻止合併，因此請保留 CI 供應商的必需檢查以執行通過/失敗強制規則。
- **發現項：** 失敗測試和不穩定測試會顯示為全量變更發現項，並連結到 Tuist 上的測試用例。發現項不會貢獻到 Entire 的 Agent 審查閘門。
- **摘要評論：** 與 GitHub 和 Origin 上的拉取請求評論類似，每個專案會為每個 Trail 保留一條 Tuist 運行報告評論。如果你刪除它，下一份報告會再次發佈它。

當新結果到達時，Tuist 會為 Trail 的當前頭部提交發佈更新的報告，並解決它所取代的發現項。重試不會創建重複的審查、發現項或評論，包括當 Entire 對發佈的響應丟失時。打開或重新打開 Trail 會獲取已為其頭部提交上傳的結果。如果當前頭部提交沒有結果，Tuist 不會發佈任何新內容，因此舊提交的閘門無法滿足新頭部的要求。已關閉和已合併的 Trails 不會更新。

Entire 卡片列出專案到儲存庫的連接。在專案連接上選擇 **Manage → Remove connection** 以停止其報告，而無需卸載外掛程式。已發佈的報告仍保留在 Entire 上，重新連接會開始新的報告。要更改外掛程式的儲存庫訪問權限或卸載它，請使用 Entire 中專案的 **Plugins** 設定。

## 自託管伺服器 {#server-configuration}

如果你託管自己的 Tuist 伺服器，請先為你的部署註冊並配置 Entire 外掛程式。按照 <.localized_link href="/guides/server/self-host/server#platform-entire">Entire 自託管說明</.localized_link> 操作，然後返回上述設定步驟以連接帳戶和專案。
