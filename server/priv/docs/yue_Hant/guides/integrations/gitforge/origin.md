---
{
  "title": "Origin",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "將原生 Cursor Origin 儲存庫連接到 Tuist Pull Request 報告。"
}
---
# Origin 整合 {#origin}

Tuist 可以在原生 [Cursor Origin](https://cursor.com/docs/api/origin) 儲存庫的拉取請求上發布建置、測試、預覽和套件報告。它會更新應用程式現有的 Tuist Run Report，而不是為每次上傳發布新評論。

安裝應用程式不會執行建置或測試。你現有的工作流程會繼續將結果上傳到 Tuist，而整合功能會將這些結果帶入你的拉取請求中。

## 設定 {#setup}

Tuist 帳戶的管理員應開啟 **Settings → Integrations**，在 Origin 卡片中選擇 **Install Origin App**，並在 Cursor 中批准存取權限。選擇 Tuist 應存取的 Origin 帳戶或命名空間及儲存庫，然後返回 Tuist。該連線屬於 Tuist 帳戶，而非單一專案。

你也可以直接從 Origin 安裝應用程式。批准存取權限後，如有需要請登入 Tuist 並選擇要連接的組織。只有你管理的組織和你的個人帳戶可供選擇。如果只有一個帳戶可用，Tuist 會自動連接該帳戶而不顯示選擇器。如果你從 Tuist 開始操作，組織已經被選中，此步驟會被跳過。

選擇 **Add new project connection** 以開啟儲存庫選擇視窗。選擇一個未連接的 Tuist 專案和從已連接的 Origin 帳戶中發現的其中一個儲存庫，然後選擇 **Create Connection**。如果連接了多個 Origin 帳戶，請先選擇帳戶。只有原生 Origin 儲存庫可供連接。Tuist 會在連接專案前再次驗證拉取請求存取權限，並採用儲存庫的預設分支。

使用 **Manage integration** 在新分頁中開啟 Cursor 的同意流程，並調整儲存庫存取權限或連接另一個 Origin 帳戶。儲存庫載入失敗時會顯示 **Retry**，這與成功的空儲存庫列表不同。

使用 <.localized_link href="/guides/server/authentication#account-tokens">帳戶權杖</.localized_link> 來驗證結果上傳。

## 報告與權限 {#reports-and-permissions}

在批准應用程式時，你授予連接儲存庫和發布報告所需的權限：

| 權限 | 用途 |
| --- | --- |
| 拉取請求：讀取 | 尋找已報告提交的開啟拉取請求。 |
| 拉取請求審查：讀取和寫入 | 讀取、發布和更新 Tuist Run Report 評論。 |
| 儲存庫元數據：讀取 | 發現儲存庫及其預設分支。由 Origin 自動包含。 |

Tuist 不需要存取你的原始碼或合併拉取請求的權限。

若要將結果與拉取請求關聯，上傳必須包含儲存庫的 Origin 克隆 URL、Git 引用和完整提交 SHA。只有當這些資訊識別出當前頭部提交的單一開啟拉取請求時，Tuist 才會發布報告。已被取代提交的結果不會覆蓋當前報告。

Origin 卡片列出專案到儲存庫的連接。在專案連接上選擇 **Manage → Remove connection** 以停止其報告，而無需解除安裝應用程式。在 Cursor 中解除安裝應用程式以撤銷其存取權限；當 Tuist 處理安裝通知時，它會移除該安裝及其專案連接。

## 自託管伺服器 {#server-configuration}

如果你託管自己的 Tuist 伺服器，請先為你的部署註冊並配置 Origin 應用程式。遵循 <.localized_link href="/guides/server/self-host/server#platform-origin">Origin 自託管說明</.localized_link>，然後返回上述設定步驟以連接帳戶和專案。
