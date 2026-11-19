---
{
  "title": "帳號與專案",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何在 Tuist 中建立與管理帳號及專案。"
}
---
# 帳號與專案 {#accounts-and-projects}

部分 Tuist 功能需要伺服器來提供資料持久化，並能與其他服務互動。若要與伺服器互動，你需要一個帳號，以及一個與本機專案連接的遠端專案。

## 帳號 {#accounts}

要使用伺服器，你需要一個帳號。帳號有兩種類型：

- **個人帳號：** 這類帳號在你註冊時自動建立，並以控點識別；控點取自身分提供者（例如 GitHub）或電子郵件地址的前半部。
- **組織帳號：** 這類帳號由開發者手動建立，並以開發者定義的控點識別。組織可以邀請其他成員共同協作專案。

如果你熟悉 [GitHub](https://github.com)，其概念類似：你可以擁有個人與組織帳號，並以用於建構 URL 的 *控點* 來識別。

你可以透過 <.localized_link href="/cli/organization">`tuist organization`</.localized_link> 下的子指令來管理組織。要建立新的組織帳號，請執行：
```bash
tuist organization create {account-handle}
```

### 組織成員資格 {#organization-membership}

使用者可以透過邀請、自動單一登入註冊，或 <.localized_link href="/guides/integrations/authentication/scim">跨網域身分管理佈建</.localized_link> 成為組織成員。

向組織的身分提供者進行驗證本身並不會授予成員資格。組織的 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">單一登入註冊政策</.localized_link> 會決定來自其信任網域的使用者是否需要邀請，或是否可以自動加入。

管理員可以從儀表板或使用 <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> 邀請成員。傳遞 `--role admin` 或 `--role viewer`，即可在受邀者接受時賦予其不同於 `user` 的角色。

### 角色 {#roles}

每位組織成員都持有以下三種角色之一：

| 角色 | 權限範圍 |
| --- | --- |
| **管理員** | 具備使用者所有權限，並可管理組織：成員與邀請、專案、帳單、權杖、Webhook 與設定。 |
| **使用者** | 可讀取並操作組織的工作：執行建置與測試、寫入快取、建立與刪除預覽，以及變更測試案例的狀態。 |
| **檢視者** | 可讀取組織的工作，但無法進行任何變更。儀表板、建置、測試執行、不穩定與隔離測試、預覽、套件與執行器活動皆可讀取。無法將互動式 Shell 或 VNC 工作階段附加至執行器，因為這會在機器上執行指令。 |

邀請他人時選擇角色，之後可在儀表板的 **成員** 中變更。以此方式設定的角色不會因後續登入而被覆寫。

## 專案 {#projects}

你的專案需要透過遠端專案與你的帳號整合。延續與 GitHub 的類比，這就像同時擁有本機與遠端儲存庫，並將變更推送到遠端。你可以使用 <.localized_link href="/cli/project">`tuist project`</.localized_link> 來建立與管理專案。

專案以完整控點識別，完整控點由組織控點與專案控點串接而成。例如，若你的組織控點為 `tuist`，專案控點為 `tuist`，則完整控點為 `tuist/tuist`。

本機與遠端專案的綁定是透過設定檔完成。如果尚未建立，請在 `Tuist.swift` 建立該檔案，並加入以下內容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **僅限 Tuist 專案的功能**
>
> 請注意，部分功能（例如 <.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>）需要由 Tuist 管理的專案。如果你未使用 Tuist 管理專案，將無法使用這些功能。


你的專案 URL 是使用完整控點建構而成。例如，Tuist 的公開儀表板可於 [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 存取，其中 `tuist/tuist` 為專案的完整控點。
