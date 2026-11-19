---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 託管平台 | 整合 | 指南 | Tuist",
  "description": "在 Entire Trails 上發布 Tuist 的建置、測試、套件與預覽洞察。"
}
---
# Entire 整合 {#entire}

Tuist 可以在 [Entire](https://entire.com) 儲存庫中開啟和草稿狀態的 [Trails](https://docs.entire.com/guides/trails/overview) 上發布建置、測試、預覽和套件的分析結果。每個 Trail 都會獲得一個 Tuist 閘道，包含執行報告、針對失敗和不穩定測試的整體變更發現，以及一個摘要評論；當新的分析結果到達時，Tuist 會更新該評論，而不是為每次上傳發布新的評論。

安裝外掛程式不會執行建置或測試。你現有的工作流程會繼續將結果上傳至 Tuist，而此整合會將這些結果帶入你的 Trails 中。

## 設定 {#setup}

Tuist 帳戶的管理員安裝外掛程式，然後將儲存庫連接至 Tuist 專案，方式與 <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> 和 <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> 整合相同。

1. 開啟你帳戶的 **Settings → Integrations**。
2. 在 Entire 卡片中，選擇 **Install Entire plugin**。選擇你想要與 Tuist 共享的 Entire 專案和儲存庫。

   ![從帳戶整合安裝 Entire 外掛程式](/images/guides/integrations/gitforge/entire/integrations.png)

3. 回到 Tuist，選擇 **Add new project connection**。在 **Choose repository to connect to** 中，選擇你的 Tuist 專案和 Entire 儲存庫，然後選擇 **Create Connection**。如果只有一個可用的 Tuist 專案，它會被自動選取。

   ![將 Tuist 專案連接至 Entire 儲存庫](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 继续使用你现有的、已认证的 Tuist 命令从 CI 上传结果，例如使用 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。Tuist 会将结果匹配到每个 Trail 的当前头部提交，因此不需要特定于 Entire 的标志。

Tuist 專案可以保留其 GitHub 連接，同時也將結果發布至 Entire，這在 Entire 儲存庫鏡像 GitHub 儲存庫時很有用。此整合不需要 Tuist 的 CI 執行器，也不會改變你的 CI 供應商。

## 報告與權限 {#reports-and-permissions}

安裝外掛程式時，你授予它尋找 Trails 和發布報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| 儲存庫內容：讀取 | 接收 Trail 事件，並找到具有其頭部提交的開啟和草稿狀態 Trails。 |
| 檢查：寫入 | 在 Trail 的頭部提交上發布 Tuist 閘道。 |
| 發現：寫入 | 將失敗和不穩定測試作為發現發布，並解決被較新報告取代的發現。 |
| 討論：寫入 | 發布並更新摘要評論。若無此權限，Tuist 仍會發布閘道和發現。 |

Tuist 不需要對你的原始碼具有寫入權限，也不需要合併 Trails 的權限。

Tuist 在每個 Trail 上發布三項內容：

- **閘道：** Tuist 檢查顯示在 **Gates** 下方，包含執行報告和指向 Tuist 上專案的連結。它列在 Tuist 外掛程式下，與 GitHub 鏡像的 **Checks** 閘道分開。它以 `neutral` 結論完成，Entire 將其顯示為通過，因為上傳的結果不會告訴 Tuist 是否每個預期的 CI 工作都已完成。即使存在發現，它也不會阻擋合併，因此請保留 CI 供應商的必要檢查以強制執行通過/失敗規則。
- **發現：** 失敗測試和不穩定測試會顯示為整體變更發現，並連結至 Tuist 上的測試案例。發現不會貢獻給 Entire 的 Agent 審查閘道。
- **摘要評論：** 如同 GitHub 和 Origin 上的拉取請求評論，每個專案會在每個 Trail 上保留一則 Tuist 執行報告評論。如果你刪除它，下一份報告會再次發布它。

當新結果到達時，Tuist 會為 Trail 的當前頭部提交發布更新的報告，並解決被取代的發現。重試不會建立重複的審查、發現或評論，包括當 Entire 對發布的回應遺失時。開啟或重新開啟 Trail 會拾取已為其頭部提交上傳的結果。如果當前頭部提交沒有結果，Tuist 不會發布任何新內容，因此較舊提交的閘道無法滿足新頭部的要求。已關閉和已合併的 Trails 不會更新。

Entire 卡片列出專案到儲存庫的連接。在專案連接上選擇 **Manage → Remove connection** 以停止其報告，而無需解除安裝外掛程式。已發布的報告會保留在 Entire 上，重新連接會開始新的報告。若要變更外掛程式的儲存庫存取權或解除安裝它，請使用 Entire 中專案的 **Plugins** 設定。

## 自託管伺服器 {#server-configuration}

如果你託管自己的 Tuist 伺服器，請先為你的部署註冊並設定 Entire 外掛程式。遵循 <.localized_link href="/guides/server/self-host/server#platform-entire">Entire 自託管說明</.localized_link>，然後返回上述設定步驟以連接帳戶和專案。
