---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "將 Tuist 嘅構建、測試、捆綁同預覽數據發佈到 Entire Trails。"
}
---
# Entire 整合 {#entire}

Tuist 可以將建置、測試、預覽和套件分析結果發布到 [Entire](https://entire.com) 儲存庫中開啟或草稿狀態的 [Trails](https://docs.entire.com/guides/trails/overview)。每個 Trail 都會獲得一個 Tuist 閘道，包含執行報告、針對失敗和不穩定測試的整次變更發現項目，以及一份摘要評論；Tuist 會在新分析結果到達時更新該評論，而非每次上傳都張貼新評論。

安裝外掛程式不會執行建置或測試。你現有的工作流程會繼續將結果上傳至 Tuist，而此整合會將這些結果帶入你的 Trails。

## 設定 {#setup}

Tuist 帳戶的管理員會先安裝外掛程式，然後將儲存庫連接至 Tuist 專案，做法與 <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> 和 <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link> 整合相同。

1. 開啟你帳戶的 **Settings → Integrations**。
2. 在 Entire 卡片中，選擇 **Install Entire plugin**。選取你想要與 Tuist 共享的 Entire 專案和儲存庫。

   ![從帳戶整合安裝 Entire 外掛程式](/images/guides/integrations/gitforge/entire/integrations.png)

3. 回到 Tuist，選擇 **Add new project connection**。在 **Choose repository to connect to** 中，選取你的 Tuist 專案和 Entire 儲存庫，然後選擇 **Create Connection**。如果只有一個可用的 Tuist 專案，系統會自動選取。

   ![將 Tuist 專案連接至 Entire 儲存庫](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. 继续使用你現有且已通過驗證的 Tuist 命令從 CI 上傳結果，例如使用 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>。Tuist 會將結果對應到每個 Trail 的當前 head commit，因此不需要任何 Entire 專屬的旗標。

Tuist 專案可以保留其 GitHub 連接，同時也將結果發布到 Entire；當 Entire 儲存庫鏡像 GitHub 儲存庫時，這很有用。此整合不需要使用 Tuist 的 CI 執行器，也不會改變你的 CI 供應商。

## 報告與權限 {#reports-and-permissions}

安裝外掛程式時，你會授予它尋找 Trails 和發布報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| Repository contents: read | 接收 Trail 事件，並找出帶有 head commits 的開啟和草稿 Trails。 |
| Checks: write | 在 Trail 的 head commit 上發布 Tuist 閘道。 |
| Findings: write | 將失敗和不穩定測試作為發現項目發布，並解決被較新報告取代的發現項目。 |
| Discussions: write | 張貼並更新摘要評論。即使沒有此權限，Tuist 仍會發布閘道和發現項目。 |

Tuist 不需要對你的原始碼具有寫入權限，也不需要合併 Trails 的權限。

Tuist 會在每個 Trail 上發布三項內容：

- **閘道：** Tuist 檢查會出現在 **Gates** 下方，包含執行報告和指向 Tuist 上專案的連結。它列在 Tuist 外掛程式之下，與 GitHub 鏡像的 **Checks** 閘道分開。它以 `neutral` 結論完成，Entire 會將其顯示為通過，因為上傳的結果不會告訴 Tuist 所有預期的 CI 工作是否已完成。即使存在發現項目，它也不會阻擋合併，因此請保留你 CI 供應商的必要檢查以執行通過/失敗強制規則。
- **發現項目：** 失敗測試和不穩定測試會顯示為整次變更發現項目，並連結到 Tuist 上的測試案例。發現項目不會計入 Entire 的 Agent 審查閘道。
- **摘要評論：** 如同 GitHub 和 Origin 上的拉取請求評論，每個專案會在每個 Trail 保留一則 Tuist Run Report 評論。如果你刪除它，下一份報告會再次張貼。

當新結果到達時，Tuist 會為 Trail 的當前 head commit 發布更新的報告，並解決被取代的發現項目。重試不會建立重複的審查、發現項目或評論，包括當 Entire 對發布的回應遺失時。開啟或重新開啟 Trail 會擷取已為其 head commit 上傳的結果。如果當前 head commit 沒有結果，Tuist 不會發布任何新內容，因此較舊 commit 的閘道無法滿足新 head 的要求。已關閉和已合併的 Trails 不會更新。

Entire 卡片列出專案到儲存庫的連接。在專案連接上選擇 **Manage → Remove connection** 以停止其報告，而無需解除安裝外掛程式。已發布的報告會保留在 Entire 上，重新連接則會開始新的報告。若要變更外掛程式的儲存庫存取權或解除安裝，請使用 Entire 中專案的 **Plugins** 設定。

## 自託管伺服器 {#server-configuration}

如果你自行託管 Tuist 伺服器，請先為你的部署註冊並設定 Entire 外掛程式。遵循 <.localized_link href="/guides/server/self-host/server#platform-entire">Entire 自託管說明</.localized_link>，然後返回上述設定步驟以連接帳戶和專案。
