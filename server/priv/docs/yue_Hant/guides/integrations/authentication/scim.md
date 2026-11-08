---
{
  "title": "SCIM 配置",
  "titleTemplate": ":title | 驗證 | 整合 | 指南 | Tuist",
  "description": "了解如何透過 Okta 或 Microsoft Entra ID 設定 SCIM 配置。"
}
---
# SCIM 供應 {#scim-provisioning}

Tuist 支援 SCIM 2.0 供應，讓身份提供者可以自動建立、更新及取消供應組織成員。

SCIM 在組織設定的 **驗證** 分頁中設定。SCIM token 是屬於組織的帳戶 token，範圍限於 SCIM 存取權限，生成時只會顯示一次。

> [!NOTE]
> SCIM 控制成員資格及生命週期。它不會取代 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>。如果已供應的使用者亦需要透過你的身份提供者登入，請另行設定 SSO。

已供應的使用者已經是組織成員。當他們以相同電郵地址登入時，該成員資格可建立信任以連結其提供者身份。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電郵網域</.localized_link> 及 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">註冊政策</.localized_link> 會控制尚未被供應或加入組織的使用者。

## Okta {#okta}

Okta 為 Tuist 使用兩個獨立的應用程式：

- 一個用於登入 Tuist 的 **OIDC Web 應用程式**。
- 一個用於向 Tuist 供應使用者及群組的 **SCIM 2.0 Test App (Header Auth)** 應用程式。

如果使用者需要使用 Okta 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>，然後按照以下步驟設定 SCIM 供應。

### 步驟 1：生成 Tuist SCIM token {#okta-step-1}

1. 在 Tuist 中，前往你組織的 **驗證** 設定分頁。
2. 在 **SCIM 供應** 部分，複製 **SCIM 端點 URL**。它應以 `/scim/v2` 結尾。
3. 點擊 **Generate token**。
4. 為 token 命名（例如 `Okta`）。
5. 複製生成的 token。Tuist 只會顯示 token 一次。

### 步驟 2：新增 Okta SCIM 應用程式 {#okta-step-2}

1. 在你的 Okta 管理儀表板中，前往 **Applications > Applications > Browse App Catalog**。
2. 搜尋並新增 **SCIM 2.0 Test App (Header Auth)**。
3. 為其命名以便識別，例如 `Tuist SCIM`。
4. 完成 SCIM 測試應用程式的登入設定。Tuist 不會使用此應用程式進行登入；登入由 SSO 指南中的 OIDC 應用程式處理。

### 步驟 3：設定 API 整合 {#okta-step-3}

1. 開啟 SCIM 應用程式的 **Provisioning** 分頁。
2. 在 **Settings > Integration** 下，點擊 **Configure API Integration** 或 **Edit**。
3. 勾選 **Enable API integration**。
4. 將 Tuist 的 **SCIM endpoint URL** 貼上到 Okta 的 **Base URL** 欄位。
5. 將 Tuist SCIM token 貼上到 **API Token**，並加上 `Bearer ` 前綴。例如 `Bearer tuist_scim_...`。Okta 會將此欄位作為 `Authorization` 標頭傳送，而 Tuist 預期收到 bearer token。
6. 如果你希望 Okta 讀取 Tuist 的 SCIM 群組，請啟用 **Import Groups**。
7. 點擊 **Test API Credentials**。Okta 應報告整合已成功驗證。
8. 點擊 **Save**。

### 步驟 4：啟用供應動作 {#okta-step-4}

1. 在 SCIM 應用程式的 **Provisioning** 分頁中，開啟 **Settings > To App**。
2. 點擊 **Edit**。
3. 啟用：
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. 點擊 **Save**。

### 步驟 5：指派使用者或群組 {#okta-step-5}

1. 開啟 SCIM 應用程式的 **Assignments** 分頁。
2. 指派應供應到 Tuist 的使用者或群組。
3. 如果這些使用者或群組也需要透過 SSO 登入，請將他們指派給 Okta OIDC 應用程式。
4. 檢查 Tuist 的 **成員** 分頁，確認已指派的使用者出現在組織中。

若要測試取消供應，請在 Okta 中取消指派或停用使用者，並確認他們從 Tuist 組織的 **成員** 分頁中消失。

### 指派角色 {#okta-assigning-roles}

Tuist 有三個 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。Tuist 為每個角色公開一個 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。使用 **Group Push** 將 Okta 群組對應到這些群組：

1. 為你想要指派的每個角色選擇或建立一個 Okta 群組，並在 SCIM 應用程式的 **Assignments** 分頁中指派這些群組。
2. 確保 API 整合中已啟用 **Import Groups**，然後開啟 SCIM 應用程式的 **Import** 分頁並點擊 **Import Now**，讓 Okta 知道 Tuist 的群組。
3. 開啟 SCIM 應用程式的 **Push Groups** 分頁，並點擊 **Push Groups > Find groups by name**。
4. 選擇一個 Okta 群組，選擇 **Link Group** 作為推送動作，並選擇對應的 Tuist 群組。Tuist 不支援透過 SCIM 建立群組，因此請連結到現有群組，而非建立新群組。
5. 點擊 **Save** 並對其餘角色重複此步驟。

將使用者加入已連結的群組會賦予他們該角色。將他們從群組中移除會使他們回到組織為單一登入成員註冊的角色，除非管理員在 **Settings > Authentication** 下更改了該設定，否則預設為 `user`。不在任何已連結群組中的使用者也會獲得該角色。從群組中移除使用者不會將他們從組織中移除；若需移除，請在 Okta 中取消指派或停用他們。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID 透過非畫廊企業應用程式供應 Tuist。如果使用者也需要使用 Entra ID 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>。

你為單一登入註冊的應用程式與用於供應的企業應用程式可以是同一個。供應是在企業應用程式項目上設定的。

### 步驟 1：生成 Tuist SCIM token {#entra-step-1}

1. 在 Tuist 中，前往你組織的 **驗證** 設定分頁。
2. 在 **SCIM 供應** 部分，複製 **SCIM 端點 URL**。它應以 `/scim/v2` 結尾。
3. 點擊 **Generate token**。
4. 為 token 命名（例如 `Entra ID`）。
5. 複製生成的 token。Tuist 只會顯示 token 一次。

### 步驟 2：設定供應 {#entra-step-2}

1. 在 Microsoft Entra 管理中心，前往 **Identity > Applications > Enterprise applications** 並開啟 Tuist 應用程式。
2. 開啟 **Provisioning** 並將 **Provisioning Mode** 設定為 **Automatic**。
3. 將 **Tenant URL** 設定為 Tuist SCIM 端點 URL。
4. 將 **Secret Token** 設定為 Tuist SCIM token。單獨輸入 token，不要加上 `Bearer ` 前綴；Entra ID 會自行添加協定。
5. 點擊 **Test Connection**。Entra ID 應報告提供的憑證已獲授權。
6. 儲存設定。

### 步驟 3：設定比對屬性 {#entra-step-3}

1. 在 **Mappings** 下，開啟 **Provision Microsoft Entra ID Users**。
2. 確認 `userPrincipalName` 或 `mail` 對應到 SCIM 的 `userName` 屬性，且該屬性是用於 **Matching precedence 1** 的屬性。
3. 如果存在，請從比對屬性中移除 `externalId`。

Tuist 透過 `userName` 比對已供應的使用者。它不會儲存 Entra ID 作為 `externalId` 傳送的目錄物件識別碼，因此針對該屬性的篩選器找不到現有成員，且供應週期可能會出現不可預測的行為。

### 步驟 4：停用群組供應 {#entra-step-4}

在 **Mappings** 下，將 **Provision Microsoft Entra ID Groups** 設定為停用。

Tuist 的 SCIM 群組是每個組織角色的固定群組，而非你可以建立的目錄群組，因此嘗試供應目錄群組會失敗。請改為按照以下說明指派角色。

### 步驟 5：指派使用者並開始供應 {#entra-step-5}

1. 開啟應用程式的 **Users and groups** 分頁，並指派應供應到 Tuist 的使用者或群組。
2. 返回 **Provisioning** 並啟動它。
3. 檢查 Tuist 的 **成員** 分頁，確認已指派的使用者出現在組織中。

Entra ID 會按其自身排程進行供應，通常每 40 分鐘一次，因此成員不會立即出現。使用 **Provision on demand** 可立即測試單一使用者。

要測試取消供應，請在 Entra ID 中取消指派或停用使用者，並確認他們從 Tuist 組織的 **成員** 分頁中消失。

如果你稍後更改供應範圍，例如從 **Sync all users and groups** 改為 **Sync only assigned users and groups**，請隨後點擊 **Restart provisioning**。Entra ID 只會在重新啟動後套用新範圍，包括取消供應不再屬於該範圍的使用者。

### 指派角色 {#entra-assigning-administrators}

Tuist 有三個 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。若要從 Entra ID 設定它們：

1. 在 **App registrations** 中，開啟 Tuist 應用程式並為你想要指派的每個 Tuist 角色新增應用程式角色。將 **Allowed member types** 設定為 **Users/Groups**，並將 **Value** 設定為 `admin`、`user` 或 `viewer`。
2. 在企業應用程式的 **Users and groups** 分頁中，為每個使用者或群組指派其中一個應用程式角色。使用者可以擁有多個應用程式角色。Tuist 會套用權限最高的角色，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`，因此屬於對應到不同角色的群組的使用者會獲得最高權限的角色。
3. 在 **Provisioning > Mappings** 下，開啟 **Advanced Options** 下拉選單並選擇 **Edit target User attributes**。新增名為 `roles` 的屬性，將 **Type** 設定為 `String`，並勾選 **Multi-Value**。
4. 在 **Provisioning > Mappings > Provision Microsoft Entra ID Users** 下，點擊 **Add New Mapping**。將 **Mapping type** 設定為 **Expression**，將 **Expression** 設定為 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`，並將 **Target attribute** 設定為你新增的 `roles` 屬性。
5. 將供應範圍保持設定為 **Sync only assigned users and groups**。`AssertiveAppRoleAssignmentsComplex` 與 **Sync all users and groups** 不相容。

`AssertiveAppRoleAssignmentsComplex` 會傳送使用者擁有的每個應用程式角色，也會傳送移除動作，因此在 Entra ID 中移除角色會將使用者降級為其仍擁有的最高權限角色。`SingleAppRoleAssignment([appRoleAssignments])` 對應到 `roles[primary eq "True"].value` 也可行，但它只會傳送一個角色，且當使用者擁有多個角色時，Entra ID 不保證會選擇哪一個。

在 Entra ID 中變更使用者的應用程式角色，會在下一個供應週期更新其 Tuist 角色。如果供應的使用者沒有應用程式角色，或其值不是 `admin`、`user` 或 `viewer`，則會獲得組織為單一登入成員註冊的角色，除非管理員在 **Settings > Authentication** 下更改了該設定，否則預設為 `user`。

## 生命週期行為 {#lifecycle-behavior}

當你的身分識別提供者將使用者指派給供應應用程式時，如果該電子郵件地址尚未被 Tuist 知悉，Tuist 會建立該使用者，然後將其加入組織。如果該電子郵件地址已屬於組織外的現有 Tuist 使用者，Tuist 會將該使用者加入並發送電子郵件通知，除非該帳戶是由另一個組織的 SCIM 整合所建立。在這種情況下，Tuist 會以 `409` 拒絕請求，以防止身分識別提供者聲稱由另一個組織管理的帳戶。

你的身分識別提供者只能在你組織自行管理帳戶期間變更使用者的電子郵件（`userName`）。這意味著 Tuist 是透過你的 SCIM 整合建立了該帳戶，且自此以來該使用者未曾設定密碼、未曾使用你組織單一登入以外的提供者登入、未曾聲明代理程式註冊，或未曾加入其他組織。對於任何其他使用者，Tuist 會以 `400` 和 `mutability` SCIM 錯誤類型拒絕變更。它仍會套用同一請求中傳送的停用動作。Tuist 也拒絕在其他組織驗證的登入網域中建立使用者或將使用者重新命名至該網域，以及在 tuist.dev 上 Tuist 自己的網域。重新命名會清除使用者證明控制舊地址的記錄。

當你的身分識別提供者取消指派或停用使用者時，Tuist 會移除其組織角色，同時保留使用者記錄及其擁有的任何工作。取消供應不會全域停用該使用者，因為同一個 Tuist 使用者可以屬於其他組織。

Tuist 公開三個合成 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。將成員加入群組會設定其組織角色。從符合其目前角色的群組中移除成員會將其移回註冊角色，而成員資格本身僅在使用者被取消指派或停用時才會結束。身分識別提供者也可以透過使用者上的 SCIM `roles` 屬性設定角色，值為 `admin`、`user` 或 `viewer`。傳送多個值的身分識別提供者會獲得其中權限最高的角色，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`。

## 支援的 SCIM 功能 {#supported-scim-features}

Tuist 支援身分識別供應商進行生命週期管理所需的 SCIM 2.0 端點：

- 針對 `/Users` 的 `POST`、`GET`、`PUT`、`PATCH` 和 `DELETE`。
- 針對 `/Groups` 的 `GET` 和 `PATCH`。
- 針對 `/ServiceProviderConfig`、`/ResourceTypes` 和 `/Schemas` 的 SCIM 探索端點。
