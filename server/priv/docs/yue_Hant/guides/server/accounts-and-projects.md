---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 帳戶與專案 {#accounts-and-projects}

部分 Tuist 功能需要伺服器來提供資料持久化，並能與其他服務互動。要與伺服器互動，你需要一個帳戶，以及一個連接到本機專案的遠端專案。

## 帳戶 {#accounts}

要使用伺服器，你需要一個帳戶。帳戶有兩種類型：

- **個人帳戶：** 這些帳戶在你註冊時自動建立，並以從身分提供者（例如 GitHub）或電子郵件地址前半部分取得的使用者名稱作為識別。
- **組織帳戶：** 這些帳戶由開發者手動建立，並以開發者定義的使用者名稱作為識別。組織可以邀請其他成員協作專案。

如果你熟悉 [GitHub](https://github.com)，其概念類似，你可以擁有個人和組織帳戶，並以用於建構 URL 的 *使用者名稱* 來識別。

> [!NOTE]
> **CLI 優先**
>
> 管理帳戶和專案的大部分操作都透過 CLI 完成。我們正在開發網頁介面，讓管理帳戶和專案更加容易。


你可以透過 <.localized_link href="/cli/organization">`tuist organization`</.localized_link> 下的子指令來管理組織。要建立新的組織帳戶，請執行：
```bash
tuist organization create {account-handle}
```

### 組織成員資格 {#organization-membership}

使用者可以透過邀請、自動單一登入註冊，或 <.localized_link href="/guides/integrations/authentication/scim">跨網域身分管理供應</.localized_link> 成為組織成員。

向組織的身分提供者進行驗證本身並不會授予成員資格。組織的 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">單一登入註冊政策</.localized_link> 會決定來自其受信任網域的使用者是否需要邀請，或是否可以自動加入。

管理員可以從儀表板或使用 <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> 邀請成員。傳遞 `--role admin` 或 `--role viewer`，以便在受邀者接受時賦予其 `user` 以外的角色。

### 角色 {#roles}

每個組織成員都持有以下三種角色之一：

| 角色 | 權限說明 |
| --- | --- |
| **管理員** | 具備使用者所有權限，加上管理組織的功能：成員與邀請、專案、計費、權杖、Webhook 和設定。 |
| **使用者** | 讀取並對組織的工作執行操作：執行建置和測試、寫入快取、建立和刪除預覽，以及變更測試案例的狀態。 |
| **檢視者** | 僅讀取組織的工作，且不進行任何變更。儀表板、建置、測試執行、不穩定與隔離測試、預覽、套件和執行器活動均可讀取。無法將互動式 Shell 或 VNC 工作階段附加到執行器，因為這會在機器上執行指令。 |

在邀請某人時選擇角色，之後可從儀表板的 **成員** 中變更。以此方式設定的角色不會因後續登入而被覆蓋。

## 專案 {#projects}

你的專案需要透過遠端專案與你的帳戶整合。延續與 GitHub 的比較，這就像擁有本機和遠端儲存庫，你可以將變更推送到遠端。你可以使用 <.localized_link href="/cli/project">`tuist project`</.localized_link> 來建立和管理專案。

專案以完整使用者名稱識別，這是將組織使用者名稱與專案使用者名稱串接後的結果。例如，如果你有一個使用者名稱為 `tuist` 的組織，以及一個使用者名稱為 `tuist` 的專案，則完整使用者名稱將為 `tuist/tuist`。

本機與遠端專案之間的綁定是透過設定檔完成。如果沒有設定檔，請在 `Tuist.swift` 建立它，並加入以下內容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **僅限 Tuist 專案的功能**
>
> 請注意，部分功能（例如 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>）需要由 Tuist 管理的專案。如果你不使用 Tuist 來管理專案，將無法使用這些功能。


你的專案 URL 是使用完整使用者名稱建構的。例如，Tuist 的公開儀表板可於 [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 存取，其中 `tuist/tuist` 是專案的完整使用者名稱。
