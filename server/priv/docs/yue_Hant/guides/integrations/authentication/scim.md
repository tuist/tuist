---
{
  "title": "SCIM 供應",
  "titleTemplate": ":title | 驗證 | 整合 | 指南 | Tuist",
  "description": "了解如何透過 Okta 或 Microsoft Entra ID 設定 SCIM 供應。"
}
---
# SCIM 配置 {#scim-provisioning}

Tuist 支援 SCIM 2.0 配置，讓身份提供者可以自動建立、更新及取消配置組織成員。

SCIM 在組織設定的 **驗證** 分頁中設定。SCIM token 是屬於組織的帳戶 token，範圍限於 SCIM 存取權限，並且只在產生時顯示一次。

> [!NOTE]
> SCIM 控制成員資格和生命週期。它不會取代 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>。如果已配置的用戶亦應透過你的身份提供者登入，請另行設定 SSO。

已配置的用戶已經是組織成員。當他們使用相同的電郵地址登入時，該成員資格可建立信任以連結其提供者身份。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電郵域名</.localized_link> 和 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">註冊政策</.localized_link> 會控制尚未配置或加入組織的用戶。

## Okta {#okta}

Okta 為 Tuist 使用兩個獨立的應用程式：

- 一個用於登入 Tuist 的 **OIDC Web 應用程式**。
- 一個用於將用戶和群組配置到 Tuist 的 **SCIM 2.0 Test App (Header Auth)** 應用程式。

如果用戶應使用 Okta 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>，然後按照以下步驟設定 SCIM 配置。

### 步驟 1：產生 Tuist SCIM token {#okta-step-1}

1. 在 Tuist 中，前往你組織的 **驗證** 設定分頁。
2. 在 **SCIM 配置** 部分，複製 **SCIM 端點 URL**。它應以 `/scim/v2` 結尾。
3. 點擊 **產生 token**。
4. 為 token 命名（例如 `Okta`）。
5. 複製產生的 token。Tuist 只會顯示 token 一次。

### 步驟 2：新增 Okta SCIM 應用程式 {#okta-step-2}

1. 在你的 Okta 管理儀表板中，前往 **Applications > Applications > Browse App Catalog**。
2. 搜尋並新增 **SCIM 2.0 Test App (Header Auth)**。
3. 為它取一個易於識別的名稱，例如 `Tuist SCIM`。
4. 完成 SCIM 測試應用程式的登入設定。Tuist 不會使用此應用程式進行登入；登入由 SSO 指南中的 OIDC 應用程式處理。

### 步驟 3：設定 API 整合 {#okta-step-3}

1. 開啟 SCIM 應用程式的 **Provisioning** 分頁。
2. 在 **Settings > Integration** 下，點擊 **Configure API Integration** 或 **Edit**。
3. 勾選 **Enable API integration**。
4. 將 Tuist 的 **SCIM 端點 URL** 貼上到 Okta 的 **Base URL** 欄位。
5. 將 Tuist SCIM token 貼上到 **API Token**，並在前面加上 `Bearer `。例如：`Bearer tuist_scim_...`。Okta 會將此欄位作為 `Authorization` 標頭傳送，而 Tuist 預期收到 bearer token。
6. 如果你希望 Okta 讀取 Tuist 的 SCIM 群組，請啟用 **Import Groups**。
7. 點擊 **Test API Credentials**。Okta 應報告整合已成功驗證。
8. 點擊 **Save**。

### 步驟 4：啟用配置動作 {#okta-step-4}

1. 在 SCIM 應用程式的 **Provisioning** 分頁中，開啟 **Settings > To App**。
2. 點擊 **Edit**。
3. 啟用：
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. 點擊 **Save**。

### 步驟 5：指派用戶或群組 {#okta-step-5}

1. 開啟 SCIM 應用程式的 **Assignments** 分頁。
2. 指派應配置到 Tuist 的用戶或群組。
3. 如果這些用戶或群組也應能透過 SSO 登入，請將相同的用戶或群組指派給 Okta OIDC 應用程式。
4. 檢查 Tuist 的 **成員** 分頁，以驗證指派的用戶是否出現在組織中。

若要測試取消配置，請在 Okta 中取消指派或停用用戶，並驗證他們是否從 Tuist 組織的 **成員** 分頁中消失。

### 指派角色 {#okta-assigning-roles}

Tuist 有三個 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。Tuist 為每個角色公開一個 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。使用 **群組推送** 將 Okta 群組對應到它們：

1. 為你想要指派的每個角色挑選或建立一個 Okta 群組，並在 SCIM 應用程式的 **Assignments** 分頁上指派這些群組。
2. 確保 API 整合中已啟用 **Import Groups**，然後開啟 SCIM 應用程式的 **Import** 分頁並點擊 **Import Now**，讓 Okta 知道 Tuist 的群組。
3. 開啟 SCIM 應用程式的 **Push Groups** 分頁，並點擊 **Push Groups > Find groups by name**。
4. 選擇一個 Okta 群組，選擇 **Link Group** 作為推送動作，並挑選相對應的 Tuist 群組。Tuist 不支援透過 SCIM 建立群組，因此請連結到現有群組，而非建立新群組。
5. 點擊 **Save**，並對其餘角色重複此步驟。

將用戶加入已連結的群組會賦予該角色。將他們從群組中移除會將他們移回組織註冊單一登入成員時的角色，除非管理員在 **Settings > Authentication** 下更改了它，否則該角色為 `user`。不在任何已連結群組中的用戶也會獲得該角色。從群組中移除用戶並不會將他們從組織中移除；若要做到這一點，請在 Okta 中取消指派或停用他們。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID 透過非畫廊企業應用程式配置 Tuist。如果用戶也應使用 Entra ID 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>。

你為單一登入註冊的應用程式與你用於配置的企業應用程式可以是同一個。配置是在企業應用程式條目中設定的。

### 步驟 1：產生 Tuist SCIM token {#entra-step-1}

1. 在 Tuist 中，前往你組織的 **驗證** 設定分頁。
2. 在 **SCIM 配置** 部分，複製 **SCIM 端點 URL**。它應以 `/scim/v2` 結尾。
3. 點擊 **產生 token**。
4. 為 token 命名（例如 `Entra ID`）。
5. 複製產生的 token。Tuist 只會顯示 token 一次。

### 步驟 2：設定配置 {#entra-step-2}

1. 在 Microsoft Entra 管理中心，前往 **Identity > Applications > Enterprise applications** 並開啟 Tuist 應用程式。
2. 開啟 **Provisioning** 並將 **Provisioning Mode** 設定為 **Automatic**。
3. 將 **Tenant URL** 設定為 Tuist SCIM 端點 URL。
4. 將 **Secret Token** 設定為 Tuist SCIM token。單獨輸入 token，不要加上 `Bearer ` 前綴；Entra ID 會自行添加方案。
5. 點擊 **Test Connection**。Entra ID 應報告提供的憑證已獲授權。
6. 儲存設定。

### 步驟 3：設定比對屬性 {#entra-step-3}

1. 在 **Mappings** 下，開啟 **Provision Microsoft Entra ID Users**。
2. 確認 `userPrincipalName` 或 `mail` 對應到 SCIM `userName` 屬性，並且該屬性是用於 **Matching precedence 1** 的屬性。
3. 如果存在 `externalId`，請從比對屬性中移除它。

Tuist 透過 `userName` 比對已配置的用戶。它不會儲存 Entra ID 作為 `externalId` 傳送的目錄物件識別碼，因此對該屬性的篩選器找不到現有成員，且配置週期的行為可能無法預測。

### 步驟 4：停用群組配置 {#entra-step-4}

在 **Mappings** 下，將 **Provision Microsoft Entra ID Groups** 設定為停用。

Tuist 的 SCIM 群組是每個組織角色的固定群組，而不是你可以建立的目錄群組，因此嘗試配置目錄群組會失敗。請改為按照下述方式指派角色。

### 步驟 5：指派用戶並開始配置 {#entra-step-5}

1. 開啟應用程式的 **Users and groups** 分頁，並指派應配置到 Tuist 的用戶或群組。
2. 返回 **Provisioning** 並啟動它。
3. 檢查 Tuist 的 **成員** 分頁，以驗證指派的用戶是否出現在組織中。

Entra ID 會按其自身排程進行配置，通常每 40 分鐘一次，因此成員不會立即出現。使用 **Provision on demand** 可立即測試單一用戶。

若要測試取消配置，請在 Entra ID 中取消指派或停用用戶，並驗證他們是否從 Tuist 組織的 **成員** 分頁中消失。

如果你稍後更改配置範圍，例如從 **Sync all users and groups** 改為 **Sync only assigned users and groups**，請隨後點擊 **Restart provisioning**。Entra ID 僅在重新啟動後才會套用新範圍，包括取消配置不再屬於該範圍的用戶。

### 指派角色 {#entra-assigning-administrators}

Tuist 有三個<.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。若要從 Entra ID 設定它們：

1. 在 **App registrations** 中，開啟 Tuist 應用程式，並為你想要指派的每個 Tuist 角色新增應用程式角色。將 **Allowed member types** 設定為 **Users/Groups**，並將 **Value** 設定為 `admin`、`user` 或 `viewer`。
2. 在企業應用程式的 **Users and groups** 分頁上，為每個用戶或群組指派其中一個應用程式角色。用戶可以擁有多個應用程式角色。Tuist 會套用權限最高的角色，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`，因此屬於對應到不同角色的群組的用戶將獲得其中最高權限的角色。
3. 在 **Provisioning > Mappings** 下，開啟 **Advanced Options** 下拉選單並選擇 **Edit target User attributes**。新增一個名為 `roles` 的屬性，將 **Type** 設定為 `String`，並勾選 **Multi-Value**。
4. 在 **Provisioning > Mappings > Provision Microsoft Entra ID Users** 下，點擊 **Add New Mapping**。將 **Mapping type** 設定為 **Expression**，將 **Expression** 設定為 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`，並將 **Target attribute** 設定為你新增的 `roles` 屬性。
5. 保持配置範圍設定為 **Sync only assigned users and groups**。`AssertiveAppRoleAssignmentsComplex` 與 **Sync all users and groups** 不相容。

`AssertiveAppRoleAssignmentsComplex` 會傳送用戶持有的每個應用程式角色，也會傳送移除操作，因此在 Entra ID 中移除角色會將用戶降級為其仍持有的最高權限角色。`SingleAppRoleAssignment([appRoleAssignments])` 對應到 `roles[primary eq "True"].value` 也可行，但它只會傳送一個角色，且當用戶擁有多個角色時，Entra ID 不保證會選擇哪一個。

在 Entra ID 中更改用戶的應用程式角色，會在下一個配置週期更新其 Tuist 角色。如果配置的用戶沒有應用程式角色，或其值不是 `admin`、`user` 或 `viewer`，則會獲得組織註冊單一登入成員時的角色，除非管理員在 **Settings > Authentication** 下進行了更改，否則該角色為 `user`。

## 生命週期行為 {#lifecycle-behavior}

當你的身分識別提供者將用戶指派給配置應用程式時，如果 Tuist 尚未知道該電子郵件，Tuist 會建立該用戶，然後將其加入組織。如果該電子郵件已屬於組織外的現有 Tuist 用戶，Tuist 會拒絕請求，以防止身分識別提供者聲稱其未在該組織中管理的用戶。

當你的身分識別提供者取消指派或停用用戶時，Tuist 會移除其組織角色，同時保留用戶記錄及其擁有的任何工作成果。取消配置不會全域停用該用戶，因為同一個 Tuist 用戶可以屬於其他組織。

Tuist 公開三個合成 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。將成員加入群組會設定其組織角色。從與其目前角色相符的群組中移除成員，會將其移回註冊角色，而成員資格本身僅在用戶被取消指派或停用時才會結束。身分識別提供者也可以透過用戶上的 SCIM `roles` 屬性來設定角色，其值為 `admin`、`user` 或 `viewer`。傳送多個值的身分識別提供者會取得其中權限最高的值，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`。

## 支援的 SCIM 功能 {#supported-scim-features}

Tuist 支援身分識別供應商進行生命週期管理所需的 SCIM 2.0 端點：

- 用於 `/Users` 的 `POST`、`GET`、`PUT`、`PATCH` 和 `DELETE`。
- 用於 `/Groups` 的 `GET` 和 `PATCH`。
- 用於 `/ServiceProviderConfig`、`/ResourceTypes` 和 `/Schemas` 的 SCIM 探索端點。
