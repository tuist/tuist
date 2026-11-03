---
{
  "title": "帳戶與專案",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何在 Tuist 中建立及管理帳戶和專案。"
}
---
# 帳戶與專案 {#accounts-and-projects}

部分 Tuist 功能需要伺服器來提供資料持久化，並能與其他服務互動。要與伺服器互動，你需要一個帳戶，以及一個連接到本機專案的遠端專案。

## 帳戶 {#accounts}

要使用伺服器，你需要一個帳戶。帳戶有兩種類型：

- **個人帳戶：** 這些帳戶會在你註冊時自動建立，並以從身分提供者（例如 GitHub）或電郵地址前半部分取得的使用者名稱來識別。
- **組織帳戶：** 這些帳戶由開發人員手動建立，並以開發人員定義的使用者名稱來識別。組織可以邀請其他成員協作專案。

如果你熟悉 [GitHub](https://github.com)，其概念類似，你可以擁有個人和組織帳戶，並以用於建構 URL 的 *使用者名稱* 來識別。

> [!NOTE]
> **CLI 優先**
>
> 大多數管理帳戶和專案的操作都透過 CLI 完成。我們正在開發網頁介面，讓管理帳戶和專案更容易。


你可以透過 <.localized_link href="/cli/organization">`tuist organization`</.localized_link> 下的子指令來管理組織。要建立新的組織帳戶，請執行：
```bash
tuist organization create {account-handle}
```

### 組織成員資格 {#organization-membership}

用戶可以透過邀請、自動單一登入註冊，或 <.localized_link href="/guides/integrations/authentication/scim">跨域身分管理系統佈建</.localized_link> 成為組織成員。

使用組織的身分提供者進行驗證本身並不會授予成員資格。組織的 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">單一登入註冊政策</.localized_link> 決定來自其受信任網域的用戶是否需要邀請，或是否可以自動加入。

管理員可以從儀表板或使用 <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> 邀請成員。傳遞 `--role admin` 或 `--role viewer`，以便在受邀者接受時賦予其 `user` 以外的角色。

### 角色 {#roles}

每個組織成員都持有以下三種角色之一：

| 角色 | 權限 |
| --- | --- |
| **管理員** | 擁有用戶的所有權限，加上管理組織的功能：成員與邀請、專案、帳單、令牌、webhooks 和設定。 |
| **用戶** | 讀取並對組織的工作執行操作：執行建置和測試、寫入快取、建立和刪除預覽，以及更改測試案例的狀態。 |
| **檢視者** | 僅讀取組織的工作，且不進行任何更改。儀表板、建置、測試運行、不穩定和被隔離的測試、預覽、套件以及執行器活動均可讀取。但無法將互動式 shell 或 VNC 工作階段附加到執行器，因為這會在機器上執行命令。 |

在邀請某人時選擇角色，之後可以在儀表板的 **成員** 中更改。以此方式設定的角色不會被後續登入覆蓋。

## 專案 {#projects}

你的專案需要透過遠端專案與你的帳戶整合。繼續與 GitHub 比較，這就像擁有本機和遠端儲存庫，你可以將變更推送到遠端。你可以使用 <.localized_link href="/cli/project">`tuist project`</.localized_link> 來建立和管理專案。

專案以完整使用者名稱識別，這是組織使用者名稱和專案使用者名稱連接的結果。例如，如果你的組織使用者名稱為 `tuist`，專案使用者名稱為 `tuist`，則完整使用者名稱為 `tuist/tuist`。

本機與遠端專案之間的綁定是透過設定檔案完成的。如果沒有設定檔案，請在 `Tuist.swift` 建立它並添加以下內容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **僅限 Tuist 專案的功能**
>
> 請注意，某些功能（如 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>）需要由 Tuist 管理的專案。如果你不使用 Tuist 來管理專案，將無法使用這些功能。


你的專案 URL 是使用完整使用者名稱建構的。例如，Tuist 的公開儀表板可於 [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 存取，其中 `tuist/tuist` 是專案的完整使用者名稱。
