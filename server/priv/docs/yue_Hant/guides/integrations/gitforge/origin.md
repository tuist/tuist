---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "將原生 Cursor Origin 儲存庫連接至 Tuist 拉取請求報告。"
}
---
# Origin 整合 {#origin}

Tuist 可以在原生 [Cursor Origin](https://cursor.com/docs/api/origin) 儲存庫的拉取請求上發布構建、測試、預覽及套件報告。它會更新應用程式現有的 Tuist Run Report，而不會為每次上傳發布新評論。

安裝應用程式並不會執行構建或測試。你現有的工作流程會繼續將結果上傳至 Tuist，而此整合會將這些結果帶入你的拉取請求中。

## 設定 {#setup}

Tuist 帳戶的管理員應開啟 **Settings → Integrations**，在 Origin 卡片中選擇 **Install Origin App**，並在 Cursor 中批准存取權限。選擇 Tuist 應存取的 Origin 帳戶或命名空間及儲存庫，然後返回 Tuist。此連線屬於 Tuist 帳戶，而非個別專案。

你也可以直接從 Origin 安裝應用程式。批准存取權限後，如有需要請登入 Tuist 並選擇要連線的組織。只有你管理的組織及你的個人帳戶可供選擇。如果只有一個帳戶可用，Tuist 會自動連線而不顯示選擇器。如果你從 Tuist 開始操作，組織已選定，此步驟會被略過。

選擇 **Add new project connection** 以開啟儲存庫選擇視窗。選擇一個未連線的 Tuist 專案及從已連線的 Origin 帳戶中發現的其中一個儲存庫，然後選擇 **Create Connection**。如果已連線多個 Origin 帳戶，請先選擇帳戶。只有原生 Origin 儲存庫可供連線。Tuist 會在連線專案前再次驗證拉取請求存取權限，並採用儲存庫的預設分支。

使用 **Manage integration** 在新分頁中開啟 Cursor 的同意流程，並調整儲存庫存取權限或連線另一個 Origin 帳戶。儲存庫載入失敗時會顯示 **Retry**，這與成功但為空的儲存庫清單不同。

使用 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> 來驗證結果上傳。

## 報告與權限 {#reports-and-permissions}

批准應用程式時，你會授予連線儲存庫及發布報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| 拉取請求：讀取 | 尋找已報告提交對應的開啟中拉取請求。 |
| 拉取請求審查：讀取和寫入 | 讀取、發布及更新 Tuist Run Report 評論。 |
| 儲存庫元數據：讀取 | 發現儲存庫及其預設分支。由 Origin 自動包含。 |

Tuist 不需要存取你的原始碼或合併拉取請求的權限。

若要將結果與拉取請求關聯，上傳內容必須包含儲存庫的 Origin 克隆 URL、Git 引用及完整提交 SHA。只有當這些資訊識別出當前頭部提交對應的單一開啟中拉取請求時，Tuist 才會發布報告。已被取代的提交結果不會覆蓋當前報告。

Origin 卡片列出專案至儲存庫的連線。在專案連線上選擇 **Manage → Remove connection** 以停止其報告，而無需解除安裝應用程式。在 Cursor 中解除安裝應用程式以撤銷其存取權限；Tuist 會在處理安裝通知時移除該安裝及其專案連線。

## 自行託管伺服器 {#server-configuration}

如果你自行託管 Tuist 伺服器，請先為你的部署註冊並設定 Origin 應用程式。按照 <.localized_link href="/guides/server/self-host/server#platform-origin">Origin self-hosting instructions</.localized_link> 操作，然後返回上述設定步驟以連線帳戶及專案。
