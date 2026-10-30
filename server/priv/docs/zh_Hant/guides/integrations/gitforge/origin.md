---
{
  "title": "Origin",
  "titleTemplate": ":title | Git 託管平台 | 整合 | 指南 | Tuist",
  "description": "將原生 Cursor Origin 儲存庫連接至 Tuist 拉取請求報告。"
}
---
# Origin 整合 {#origin}

Tuist 可在原生 [Cursor Origin](https://cursor.com/docs/api/origin) 儲存庫的拉取請求上發布建置、測試、預覽與套件報告。它會更新應用程式現有的 Tuist 執行報告，而非為每次上傳張貼新留言。

安裝應用程式不會執行建置或測試。你現有的工作流程會繼續將結果上傳至 Tuist，而此整合會將這些結果帶入你的拉取請求中。

## 設定 {#setup}

Tuist 帳戶的管理員應開啟 **Settings → Integrations**，在 Origin 卡片中選擇 **Install Origin App**，並在 Cursor 中核准存取權。選擇 Tuist 應存取的 Origin 帳戶或命名空間與儲存庫，然後返回 Tuist。此連線屬於 Tuist 帳戶，而非單一專案。

你也可以直接從 Origin 安裝應用程式。核准存取權後，如有需要請登入 Tuist 並選擇要連線的組織。僅有你管理的組織與你的個人帳戶可供選擇。若只有一個帳戶可用，Tuist 會自動連線而不顯示選擇器。若你從 Tuist 開始操作，組織已選取，因此會略過此步驟。

選擇 **Add new project connection** 以開啟儲存庫選擇對話框。選取一個未連線的 Tuist 專案，以及從已連線的 Origin 帳戶中發現的其中一個儲存庫，然後選擇 **Create Connection**。若有多個 Origin 帳戶已連線，請先選擇帳戶。僅可連線原生 Origin 儲存庫。Tuist 會在連線專案前再次驗證拉取請求存取權，並採用儲存庫的預設分支。

使用 **Manage integration** 在新分頁中開啟 Cursor 的同意流程，並調整儲存庫存取權或連線另一個 Origin 帳戶。儲存庫載入失敗時會顯示 **Retry**，這與成功但為空的儲存庫清單不同。

使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link> 來驗證結果上傳。

## 報告與權限 {#reports-and-permissions}

核准應用程式時，你會授予連線儲存庫與發布報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| 拉取請求：讀取 | 找出已回報修訂對應的開啟中拉取請求。 |
| 拉取請求審查：讀取與寫入 | 讀取、張貼並更新 Tuist 執行報告留言。 |
| 儲存庫中繼資料：讀取 | 探索儲存庫及其預設分支。由 Origin 自動包含。 |

Tuist 不需要存取你的原始碼或合併拉取請求的權限。

若要將結果與拉取請求關聯，上傳內容必須包含儲存庫的 Origin 複製 URL、Git 參照與完整修訂 SHA。Tuist 僅在這些資訊能識別出目前頭部修訂對應的單一開啟中拉取請求時，才會張貼報告。已被取代修訂的結果不會覆寫目前報告。

Origin 卡片會列出專案對儲存庫的連線。在專案連線上選擇 **Manage → Remove connection** 即可停止其報告，而無需解除安裝應用程式。在 Cursor 中解除安裝應用程式以撤銷其存取權；Tuist 會在處理安裝通知時移除該安裝及其專案連線。

## 自行託管伺服器 {#server-configuration}

若你自行託管 Tuist 伺服器，請先為你的部署註冊並設定 Origin 應用程式。依照 <.localized_link href="/guides/server/self-host/server#platform-origin">Origin 自行託管說明</.localized_link> 操作，然後返回上述設定步驟以連線帳戶與專案。
