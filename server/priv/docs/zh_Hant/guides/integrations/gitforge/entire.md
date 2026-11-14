---
{
  "title": "Entire",
  "titleTemplate": ":title | Git 託管平台 | 整合 | 指南 | Tuist",
  "description": "在 Entire Trails 上發布 Tuist 的建置、測試、套件與預覽洞察。"
}
---
# Entire 整合 {#entire}

Tuist 可以在 [Entire](https://entire.com) 儲存庫中開啟和草稿狀態的 [Trails](https://docs.entire.com/guides/trails/overview) 上發布建置、測試、預覽與套件分析結果。每個 Trail 都會獲得一個 Tuist 閘道，包含執行報告、針對失敗和不穩定測試的整體變更發現項目，以及一份摘要留言；Tuist 會在新分析結果到達時更新該留言，而非每次上傳都張貼新留言。

安裝外掛程式並不會執行建置或測試。你現有的工作流程會繼續將結果上傳至 Tuist，而此整合會將這些結果帶入你的 Trails。

## 設定 {#setup}

Tuist 帳戶的管理員會先安裝外掛程式，然後將儲存庫連接至 Tuist 專案，做法與 <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> 和 <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> 整合相同。

1. 開啟帳戶的 **Settings → Integrations**。
2. 在 Entire 卡片中，選擇 **Install Entire plugin**。選擇你想要與 Tuist 共用的 Entire 專案和儲存庫。

   ![從帳戶整合安裝 Entire 外掛程式](/images/guides/integrations/gitforge/entire/integrations.png)

3. 回到 Tuist，選擇 **Add new project connection**。在 **Choose repository to connect to** 中，選取你的 Tuist 專案和 Entire 儲存庫，然後選擇 **Create Connection**。如果只有一個可用的 Tuist 專案，系統會自動選取。

   ![將 Tuist 專案連接至 Entire 儲存庫](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 继续使用你現有且已通過驗證的 Tuist 指令從 CI 上傳結果，例如使用 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。Tuist 會將結果比對至每個 Trail 目前的頭部提交，因此不需要任何 Entire 專屬旗標。

Tuist 專案可以保留其 GitHub 連線，同時也將結果發布至 Entire；當 Entire 儲存庫鏡像 GitHub 儲存庫時，這項功能特別有用。此整合不需要 Tuist 的 CI 執行器，也不會改變你的 CI 供應商。

## 報告與權限 {#reports-and-permissions}

安裝外掛程式時，你會授予它尋找 Trails 並發布報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| Repository contents: read | 接收 Trail 事件，並找出具有頭部提交的開啟和草稿 Trails。 |
| Checks: write | 在 Trail 的頭部提交上發布 Tuist 閘道。 |
| Findings: write | 將失敗和不穩定測試作為發現項目發布，並解決被較新報告取代的發現項目。 |
| Discussions: write | 張貼並更新摘要留言。若未授予此權限，Tuist 仍會發布閘道和發現項目。 |

Tuist 不需要對你的原始碼具備寫入權限，也不需要合併 Trails 的權限。

Tuist 會在每個 Trail 上發布三項內容：

- **閘道：** Tuist 檢查會出現在 **Gates** 下方，包含執行報告以及指向 Tuist 上專案的連結。它列在 Tuist 外掛程式底下，與 GitHub 鏡像的 **Checks** 閘道分開顯示。它以 `neutral` 結論完成，Entire 會將其顯示為通過，因為上傳的結果不會告訴 Tuist 所有預期的 CI 工作是否已完成。即使存在發現項目，它也不會阻擋合併，因此請保留 CI 供應商用於強制通過/失敗的必要檢查。
- **發現項目：** 失敗測試和不穩定測試會以整體變更發現項目的形式出現，並連結至 Tuist 上的測試案例。發現項目不會計入 Entire 的 Agent 審查閘道。
- **摘要留言：** 如同 GitHub 和 Origin 上的拉取請求留言，每個專案會為每個 Trail 保留一則 Tuist 執行報告留言。若你刪除它，下一份報告會再次張貼。

當新結果到達時，Tuist 會為 Trail 目前的頭部提交發布更新的報告，並解決被取代的發現項目。重試不會建立重複的審查、發現項目或留言，即使 Entire 對發布的回應遺失亦然。開啟或重新開啟 Trail 時，會擷取已為其頭部提交上傳的結果。若目前頭部提交沒有結果，Tuist 不會發布任何新內容，因此舊提交的閘道無法滿足新頭部的要求。已關閉和已合併的 Trails 不會更新。

Entire 卡片列出專案到儲存庫的連線。在專案連線上選擇 **Manage → Remove connection** 即可停止其報告，無需解除安裝外掛程式。已發布的報告會保留在 Entire 上，重新連線則會開始新的報告。若要變更外掛程式的儲存庫存取權或解除安裝，請使用 Entire 中專案的 **Plugins** 設定。

## 自行託管伺服器 {#server-configuration}

若你自行託管 Tuist 伺服器，請先為你的部署註冊並設定 Entire 外掛程式。依照 <.localized_link href="/guides/server/self-host/server#platform-entire">Entire 自行託管說明</.localized_link> 操作，然後回到上述設定步驟以連接帳戶和專案。
