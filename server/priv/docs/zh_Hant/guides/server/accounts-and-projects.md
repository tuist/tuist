---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 帳號與專案 {#accounts-and-projects}

部分 Tuist 功能需要伺服器來提供資料持久化，並能與其他服務互動。若要與伺服器互動，您需要一個帳號以及一個與本機專案連接的專案。

## 帳號 {#accounts}

要使用伺服器，您需要一個帳號。帳號有兩種類型：

- **個人帳號：** 這些帳號在您註冊時自動建立，並以從身分提供者（例如 GitHub）或電子郵件地址第一部分取得的使用者名稱作為識別。
- **組織帳號：** 這些帳號由開發者手動建立，並以開發者定義的使用者名稱作為識別。組織可以邀請其他成員協作專案。

如果您熟悉 [GitHub](https://github.com)，其概念類似，您可以擁有個人和組織帳號，並以用於建構 URL 的*使用者名稱*來識別。

> [!NOTE]
> **CLI 優先**
>
> 大多數管理帳號和專案的操作都是透過 CLI 完成。我們正在開發網頁介面，讓管理帳號和專案更加容易。


您可以透過 <.localized_link href="/cli/organization">`tuist organization`</.localized_link> 下的子指令來管理組織。若要建立新的組織帳號，請執行：
```bash
tuist organization create {account-handle}
```

### 組織成員資格 {#organization-membership}

使用者可以透過邀請、自動單一登入註冊，或<.localized_link href="/guides/integrations/authentication/scim">跨網域身分管理佈建</.localized_link>成為組織成員。

僅透過組織的身分提供者進行驗證並不會自動授予成員資格。組織的<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">單一登入註冊政策</.localized_link>會決定來自其受信任網域的使用者是否需要邀請，或是可以自動加入。

管理員可以從儀表板或使用 <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> 邀請成員。傳遞 `--role admin` 或 `--role viewer` 可在受邀者接受時賦予其不同於 `user` 的角色。

### 角色 {#roles}

每位組織成員都持有以下三種角色之一：

| 角色 | 權限說明 |
| --- | --- |
| **管理員** | 擁有使用者可執行的所有操作，外加管理組織：成員與邀請、專案、帳單、權杖、Webhook 和設定。 |
| **使用者** | 讀取並對組織的工作執行操作：執行建置與測試、寫入快取、建立與刪除預覽，以及變更測試案例的狀態。 |
| **檢視者** | 僅讀取組織的工作，且不進行任何變更。儀表板、建置、測試執行、不穩定與隔離測試、預覽、套件包以及執行器活動均可讀取。但無法將互動式 Shell 或 VNC 工作階段附加至執行器，因為這會在機器上執行命令。 |

在邀請某人時選擇角色，之後可從儀表板的**成員**中變更。以此方式設定的角色不會因後續登入而被覆寫。

## 專案 {#projects}

您的專案需要透過遠端專案與您的帳號整合。延續與 GitHub 的比較，這就像擁有本機和遠端儲存庫，您可以將變更推送至遠端。您可以使用 <.localized_link href="/cli/project">`tuist project`</.localized_link> 來建立和管理專案。

專案以完整使用者名稱識別，這是將組織使用者名稱與專案使用者名稱串接後的結果。例如，若您有一個使用者名稱為 `tuist` 的組織，以及一個使用者名稱為 `tuist` 的專案，則完整使用者名稱將為 `tuist/tuist`。

本機與遠端專案之間的綁定是透過設定檔完成。若尚無設定檔，請在 `Tuist.swift` 建立並加入以下內容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **僅限 Tuist 專案的功能**
>
> 請注意，部分功能（例如<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>）需要由 Tuist 管理的專案。若您未使用 Tuist 管理專案，將無法使用這些功能。


您的專案 URL 是使用完整使用者名稱建構而成。例如，Tuist 的公開儀表板可於 [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 存取，其中 `tuist/tuist` 是專案的完整使用者名稱。
