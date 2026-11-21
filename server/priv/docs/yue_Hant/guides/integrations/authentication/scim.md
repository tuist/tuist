---
{
  "title": "SCIM 配置",
  "titleTemplate": ":title | Authentication | Integrations | Guides | Tuist",
  "description": "了解如何透過 Okta 或 Microsoft Entra ID 設定 SCIM 配置。"
}
---
# SCIM 配置 {#scim-provisioning}

Tuist 支援 SCIM 2.0 配置，讓身份提供者可以自動建立、更新及撤銷組織成員。

你可以在組織設定的 **Authentication** 分頁中設定 SCIM。SCIM token 是屬於組織的帳戶 token，範圍限於 SCIM 存取權限，並且只在生成時顯示一次。

> [!NOTE]
> SCIM 控制成員資格和生命週期。它不會取代 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>。如果已配置的用戶亦需要透過你的身份提供者登入，請另行設定 SSO。

已配置的用戶已經是組織成員。當他們使用相同的電郵地址登入時，該成員資格可以建立信任以連結其提供者身份。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">verified login email domain</.localized_link> 和 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">enrollment policy</.localized_link> 用於控制尚未配置或加入組織的用戶。

## Okta {#okta}

Okta 為 Tuist 使用兩個獨立的應用程式：

- 一個用於登入 Tuist 的 **OIDC Web Application**。
- 一個用於將用戶和群組配置到 Tuist 的 **SCIM 2.0 Test App (Header Auth)** 應用程式。

如果用戶需要使用 Okta 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>，然後按照以下步驟設定 SCIM 配置。

### 步驟 1：生成 Tuist SCIM token {#okta-step-1}

1. 在 Tuist 中，前往你組織的 **Authentication** 設定分頁。
2. 在 **SCIM provisioning** 部分，複製 **SCIM endpoint URL**。它應該以 `/scim/v2` 結尾。
3. 點擊 **Generate token**。
4. 為 token 命名（例如 `Okta`）。
5. 複製生成的 token。Tuist 只會顯示 token 一次。

### 步驟 2：新增 Okta SCIM 應用程式 {#okta-step-2}

1. 在你的 Okta 管理儀表板中，前往 **Applications > Applications > Browse App Catalog**。
2. 搜尋並新增 **SCIM 2.0 Test App (Header Auth)**。
3. 為其取一個易於識別的名稱，例如 `Tuist SCIM`。
4. 完成 SCIM 測試應用程式的登入設定。Tuist 不會使用此應用程式進行登入；登入由 SSO 指南中的 OIDC 應用程式處理。

### 步驟 3：設定 API 整合 {#okta-step-3}

1. 開啟 SCIM 應用程式的 **Provisioning** 分頁。
2. 在 **Settings > Integration** 下，點擊 **Configure API Integration** 或 **Edit**。
3. 勾選 **Enable API integration**。
4. 將 Tuist 的 **SCIM endpoint URL** 貼上到 Okta 的 **Base URL** 欄位。
5. 將 Tuist SCIM token 貼上到 **API Token**，並在前面加上 `Bearer `。例如：`Bearer tuist_scim_...`。Okta 會將此欄位作為 `Authorization` header 發送，而 Tuist 預期收到 bearer token。
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

### 步驟 5：分配用戶或群組 {#okta-step-5}

1. 開啟 SCIM 應用程式的 **Assignments** 分頁。
2. 分配應配置到 Tuist 的用戶或群組。
3. 如果這些用戶或群組也需要透過 SSO 登入，請將相同的用戶或群組分配到 Okta OIDC 應用程式。
4. 檢查 Tuist 的 **Members** 分頁，以驗證已分配的用戶是否出現在組織中。

要測試取消配置，請在 Okta 中取消分配或停用用戶，並驗證他們是否從 Tuist 組織的 **Members** 分頁中消失。

### 分配角色 {#okta-assigning-roles}

Tuist 有三個 <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link>：`admin`、`user` 和 `viewer`。Tuist 為每個角色公開一個 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。使用 **Group Push** 將 Okta 群組映射到它們：

1. 為你想要分配的每個角色選擇或建立一個 Okta 群組，並在 SCIM 應用程式的 **Assignments** 分頁中分配這些群組。
2. 確保 API 整合中已啟用 **Import Groups**，然後開啟 SCIM 應用程式的 **Import** 分頁並點擊 **Import Now**，讓 Okta 知悉 Tuist 的群組。
3. 開啟 SCIM 應用程式的 **Push Groups** 分頁，並點擊 **Push Groups > Find groups by name**。
4. 選擇一個 Okta 群組，選擇 **Link Group** 作為推送動作，並選擇對應的 Tuist 群組。Tuist 不支援透過 SCIM 建立群組，因此請連結到現有群組，而非建立新群組。
5. 點擊 **Save**，並對其餘角色重複此步驟。

將用戶加入已連結的群組會賦予他們該角色。將他們從群組中移除會使他們恢復到組織註冊單一登入成員時的角色，除非管理員在 **Settings > Authentication** 下更改了該設定，否則該角色為 `user`。不在任何已連結群組中的用戶也會獲得該角色。從群組中移除用戶不會將他們從組織中移除；若要做到這一點，請在 Okta 中取消分配或停用他們。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID 透過非畫廊企業應用程式為 Tuist 進行配置。如果用戶也需要使用 Entra ID 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>。

你為單一登入註冊的應用程式與用於配置的企業應用程式可以是同一個。配置是在企業應用程式條目中設定的。

### 步驟 1：生成 Tuist SCIM token {#entra-step-1}

1. 在 Tuist 中，前往你組織的 **Authentication** 設定分頁。
2. 在 **SCIM provisioning** 部分，複製 **SCIM endpoint URL**。它應該以 `/scim/v2` 結尾。
3. 點擊 **Generate token**。
4. 為 token 命名（例如 `Entra ID`）。
5. 複製生成的 token。Tuist 只會顯示 token 一次。

### 步驟 2：設定配置 {#entra-step-2}

1. 在 Microsoft Entra 管理中心，前往 **Identity > Applications > Enterprise applications** 並開啟 Tuist 應用程式。
2. 開啟 **Provisioning** 並將 **Provisioning Mode** 設定為 **Automatic**。
3. 將 **Tenant URL** 設定為 Tuist SCIM endpoint URL。
4. 將 **Secret Token** 設定為 Tuist SCIM token。單獨輸入 token，不要加上 `Bearer ` 前綴；Entra ID 會自行添加協議。
5. 點擊 **Test Connection**。Entra ID 應報告提供的憑證已獲授權。
6. 儲存設定。

### 步驟 3：設定匹配屬性 {#entra-step-3}

1. 在 **Mappings** 下，開啟 **Provision Microsoft Entra ID Users**。
2. 確認 `userPrincipalName` 或 `mail` 映射到 SCIM `userName` 屬性，並且該屬性是用於 **Matching precedence 1** 的屬性。
3. 如果存在 `externalId`，請從匹配屬性中將其移除。

Tuist 透過 `userName` 匹配已配置的用戶。它不會儲存 Entra ID 作為 `externalId` 發送的目錄物件識別碼，因此對該屬性的篩選器無法找到現有成員，且配置週期可能會出現不可預測的行為。

### 步驟 4：停用群組配置 {#entra-step-4}

在 **Mappings** 下，將 **Provision Microsoft Entra ID Groups** 設定為停用。

Tuist 的 SCIM 群組是每個組織角色的固定群組，而不是你可以建立的目錄群組，因此嘗試配置目錄群組會失敗。請改為按照下述方式分配角色。

### 步驟 5：分配用戶並開始配置 {#entra-step-5}

1. 開啟應用程式的 **Users and groups** 分頁，並分配應配置到 Tuist 的用戶或群組。
2. 返回 **Provisioning** 並啟動它。
3. 檢查 Tuist 的 **Members** 分頁，以驗證已分配的用戶是否出現在組織中。

Entra ID 會按照自己的排程進行配置，通常每 40 分鐘一次，因此成員不會立即出現。使用 **Provision on demand** 可立即測試單一用戶。

要測試取消配置，請在 Entra ID 中取消分配或停用用戶，並驗證他們是否從 Tuist 組織的 **Members** 分頁中消失。

如果你稍後更改配置範圍，例如從 **Sync all users and groups** 改為 **Sync only assigned users and groups**，請隨後點擊 **Restart provisioning**。Entra ID 只會在重新啟動後應用新範圍，包括取消配置不再屬於該範圍的用戶。

### 分配角色 {#entra-assigning-administrators}

Tuist 有三種 <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link>：`admin`、`user` 和 `viewer`。若要從 Entra ID 設定它們：

1. 在 **App registrations** 中，開啟 Tuist 應用程式並為你想要分配的每個 Tuist 角色添加一個應用程式角色。將 **Allowed member types** 設定為 **Users/Groups**，並將 **Value** 設定為 `admin`、`user` 或 `viewer`。
2. 在企業應用程式的 **Users and groups** 分頁上，為每個用戶或群組分配其中一個應用程式角色。用戶可以擁有多個應用程式角色。Tuist 會應用權限最高的一個，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`，因此屬於映射到不同角色的群組的用戶將獲得其中最高的角色。
3. 在 **Provisioning > Mappings** 下，開啟 **Advanced Options** 下拉選單並選擇 **Edit target User attributes**。添加一個名為 `roles` 的屬性，將 **Type** 設定為 `String` 並勾選 **Multi-Value**。
4. 在 **Provisioning > Mappings > Provision Microsoft Entra ID Users** 下，點擊 **Add New Mapping**。將 **Mapping type** 設定為 **Expression**，**Expression** 設定為 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`，並將 **Target attribute** 設定為你添加的 `roles` 屬性。
5. 保持配置範圍設定為 **Sync only assigned users and groups**。`AssertiveAppRoleAssignmentsComplex` 與 **Sync all users and groups** 不相容。

`AssertiveAppRoleAssignmentsComplex` 會發送用戶擁有的每個應用程式角色，也會發送移除操作，因此在 Entra ID 中移除角色會將用戶降級為他們仍持有的最高權限角色。`SingleAppRoleAssignment([appRoleAssignments])` 映射到 `roles[primary eq "True"].value` 也有效，但它只會發送一個角色，且當用戶擁有多個角色時，Entra ID 不保證會選擇哪一個。

在 Entra ID 中更改用戶的應用程式角色會在下一個配置週期更新其 Tuist 角色。如果配置的用戶沒有應用程式角色，或者具有 `admin`、`user` 或 `viewer` 以外的值，則會獲得組織註冊單點登錄成員時的角色，除非管理員在 **Settings > Authentication** 下更改了該角色，否則預設為 `user`。

## 生命週期行為 {#lifecycle-behavior}

當你的身份提供者將用戶分配到配置應用程式時，如果 Tuist 尚不知道該電子郵件，Tuist 會創建該用戶，然後將其添加到組織中。如果該電子郵件已屬於組織外的現有 Tuist 用戶，Tuist 會添加該用戶並通過電子郵件通知他們，除非該帳戶是由另一個組織的 SCIM 集成創建的。在這種情況下，Tuist 會以 `409` 拒絕請求，以防止身份提供者聲稱另一個組織管理的帳戶。

只有當你的組織獨立管理帳戶時，你的身份提供者才能更改用戶的電子郵件（`userName`）。這意味著 Tuist 是透過你的 SCIM 集成創建了該帳戶，並且此後該用戶尚未設定密碼、未使用組織單點登錄以外的提供者登錄、未聲明代理註冊，也未加入其他組織。對於任何其他用戶，Tuist 會以 `400` 和 `mutability` SCIM 錯誤類型拒絕更改。它仍然會應用在同一請求中發送的停用操作。Tuist 也拒絕在其他組織驗證的登錄域中創建用戶或將用戶重命名到該域，以及在 tuist.dev 上 Tuist 自己的域。重命名會清除用戶證明控制舊地址的記錄。

當你的身份提供者取消分配或停用用戶時，Tuist 會移除他們的組織角色，同時保留用戶記錄和他們擁有的任何工作。取消配置不會全局禁用用戶，因為同一個 Tuist 用戶可以屬於其他組織。

Tuist 公開三個合成 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。將成員添加到群組會設定其組織角色。從與其當前角色匹配的群組中移除成員會將其移回註冊角色，而成員資格本身僅在用戶被取消分配或停用時才會結束。身份提供者也可以透過用戶上的 SCIM `roles` 屬性設定角色，值為 `admin`、`user` 或 `viewer`。發送多個值的身份提供者會獲得其中權限最高的一個，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`。

## 支援的 SCIM 功能 {#supported-scim-features}

Tuist 支援身份提供者進行生命週期管理所需的 SCIM 2.0 端點：

- 針對 `/Users` 的 `POST`、`GET`、`PUT`、`PATCH` 和 `DELETE`。
- 針對 `/Groups` 的 `GET` 和 `PATCH`。
- 針對 `/ServiceProviderConfig`、`/ResourceTypes` 和 `/Schemas` 的 SCIM 探索端點。
