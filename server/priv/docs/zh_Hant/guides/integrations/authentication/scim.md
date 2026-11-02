---
{
  "title": "SCIM 佈建",
  "titleTemplate": ":title | 驗證 | 整合 | 指南 | Tuist",
  "description": "了解如何搭配 Okta 或 Microsoft Entra ID 設定 SCIM 佈建。"
}
---
# SCIM 佈建 {#scim-provisioning}

Tuist 支援 SCIM 2.0 佈建，讓身分識別提供者能自動建立、更新與撤銷組織成員。

在組織設定的 **驗證** 頁籤中設定 SCIM。SCIM Token 是屬於組織的帳號 Token，範圍限定於 SCIM 存取權限，且僅在產生時顯示一次。

> [!NOTE]
> SCIM 控制成員資格與生命週期。它不會取代 <.localized_link href="/guides/integrations/authentication/sso">單一登入</.localized_link>。若已佈建的使用者也需要透過你的身分識別提供者登入，請另外設定 SSO。

已佈建的使用者已是組織成員。當他們以相同電子郵件地址登入時，該成員資格可建立信任以連結其提供者身分。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已驗證的登入電子郵件網域</.localized_link>與 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">註冊政策</.localized_link> 會控制尚未佈建或未加入組織的使用者。

## Okta {#okta}

Okta 為 Tuist 使用兩個獨立的應用程式：

- 用於登入 Tuist 的 **OIDC Web 應用程式**。
- 用於將使用者與群組佈建至 Tuist 的 **SCIM 2.0 Test App (Header Auth)** 應用程式。

若使用者需以 Okta 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>，再依照以下步驟設定 SCIM 佈建。

### 步驟 1：產生 Tuist SCIM Token {#okta-step-1}

1. 在 Tuist 中，前往你組織的 **驗證** 設定頁籤。
2. 在 **SCIM 佈建** 區段中，複製 **SCIM 端點 URL**。它應以 `/scim/v2` 結尾。
3. 點擊 **產生 Token**。
4. 為 Token 命名（例如 `Okta`）。
5. 複製產生的 Token。Tuist 僅在產生時顯示一次 Token。

### 步驟 2：新增 Okta SCIM 應用程式 {#okta-step-2}

1. 在你的 Okta 管理儀表板中，前往 **Applications > Applications > Browse App Catalog**。
2. 搜尋並新增 **SCIM 2.0 Test App (Header Auth)**。
3. 為其取一個易於識別的名稱，例如 `Tuist SCIM`。
4. 完成 SCIM 測試應用程式的登入設定。Tuist 不會使用此應用程式進行登入；登入由 SSO 指南中的 OIDC 應用程式處理。

### 步驟 3：設定 API 整合 {#okta-step-3}

1. 開啟 SCIM 應用程式的 **Provisioning** 頁籤。
2. 在 **Settings > Integration** 下方，點擊 **Configure API Integration** 或 **Edit**。
3. 勾選 **Enable API integration**。
4. 將 Tuist 的 **SCIM 端點 URL** 貼到 Okta 的 **Base URL** 欄位。
5. 將 Tuist SCIM Token 貼到 **API Token**，並在前方加上 `Bearer `。例如：`Bearer tuist_scim_...`。Okta 會將此欄位作為 `Authorization` 標頭傳送，而 Tuist 預期收到 bearer token。
6. 若你希望 Okta 讀取 Tuist 的 SCIM 群組，請啟用 **Import Groups**。
7. 點擊 **Test API Credentials**。Okta 應回報整合已成功驗證。
8. 點擊 **Save**。

### 步驟 4：啟用佈建動作 {#okta-step-4}

1. 在 SCIM 應用程式的 **Provisioning** 頁籤中，開啟 **Settings > To App**。
2. 點擊 **Edit**。
3. 啟用：
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. 點擊 **Save**。

### 步驟 5：指派使用者或群組 {#okta-step-5}

1. 開啟 SCIM 應用程式的 **Assignments** 頁籤。
2. 指派應佈建至 Tuist 的使用者或群組。
3. 若這些使用者或群組也需透過 SSO 登入，請將他們指派給相同的 Okta OIDC 應用程式。
4. 檢查 Tuist 的 **成員** 頁籤，確認已指派的使用者出現在組織中。

若要測試取消佈建，請在 Okta 中取消指派或停用使用者，並確認他們從 Tuist 組織的 **成員** 頁籤中消失。

### 指派角色 {#okta-assigning-roles}

Tuist 有三種 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。Tuist 為每種角色提供一個 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。使用 **群組推送** 將 Okta 群組對應到這些群組：

1. 為你想要指派的每個角色選擇或建立一個 Okta 群組，並在 SCIM 應用程式的 **Assignments** 頁籤中指派這些群組。
2. 確保 API 整合中已啟用 **Import Groups**，然後開啟 SCIM 應用程式的 **Import** 頁籤並點擊 **Import Now**，讓 Okta 識別 Tuist 的群組。
3. 開啟 SCIM 應用程式的 **Push Groups** 頁籤，並點擊 **Push Groups > Find groups by name**。
4. 選擇一個 Okta 群組，選擇 **Link Group** 作為推送動作，並挑選相對應的 Tuist 群組。Tuist 不支援透過 SCIM 建立群組，因此請連結至現有群組，而非建立新群組。
5. 點擊 **Save**，並對其餘角色重複此步驟。

將使用者加入已連結的群組會賦予該角色。將他們從群組中移除會使其恢復為組織註冊單一登入成員時的預設角色，除非管理員在 **Settings > Authentication** 下進行了變更，否則預設為 `user`。未屬於任何已連結群組的使用者也會獲得該角色。從群組中移除使用者不會將其從組織中移除；若需如此，請在 Okta 中取消指派或停用他們。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID 透過非畫廊企業應用程式為 Tuist 進行佈建。若使用者需以 Entra ID 登入，請先設定 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>。

你為單一登入註冊的應用程式與用於佈建的企業應用程式可以是同一個。佈建是在企業應用程式項目上進行設定。

### 步驟 1：產生 Tuist SCIM Token {#entra-step-1}

1. 在 Tuist 中，前往你組織的 **驗證** 設定頁籤。
2. 在 **SCIM 佈建** 區段中，複製 **SCIM 端點 URL**。它應以 `/scim/v2` 結尾。
3. 點擊 **產生 Token**。
4. 為 Token 命名（例如 `Entra ID`）。
5. 複製產生的 Token。Tuist 僅在產生時顯示一次 Token。

### 步驟 2：設定佈建 {#entra-step-2}

1. 在 Microsoft Entra 管理中心，前往 **Identity > Applications > Enterprise applications** 並開啟 Tuist 應用程式。
2. 開啟 **Provisioning** 並將 **Provisioning Mode** 設定為 **Automatic**。
3. 將 **Tenant URL** 設定為 Tuist SCIM 端點 URL。
4. 將 **Secret Token** 設定為 Tuist SCIM Token。單獨輸入 Token，無需加上 `Bearer ` 前綴；Entra ID 會自行添加協定。
5. 點擊 **Test Connection**。Entra ID 應回報提供的憑證已獲授權。
6. 儲存設定。

### 步驟 3：設定比對屬性 {#entra-step-3}

1. 在 **Mappings** 下方，開啟 **Provision Microsoft Entra ID Users**。
2. 確認 `userPrincipalName` 或 `mail` 對應至 SCIM `userName` 屬性，且該屬性是用於 **Matching precedence 1** 的屬性。
3. 若存在 `externalId`，請從比對屬性中移除。

Tuist 透過 `userName` 比對已佈建的使用者。它不會儲存 Entra ID 作為 `externalId` 傳送的目錄物件識別碼，因此針對該屬性的篩選器無法找到現有成員，導致佈建週期行為不可預測。

### 步驟 4：停用群組佈建 {#entra-step-4}

在 **Mappings** 下方，將 **Provision Microsoft Entra ID Groups** 設定為停用。

Tuist 的 SCIM 群組是每個組織角色的固定群組，而非你可建立的目錄群組，因此嘗試佈建目錄群組會失敗。請改為依照下述方式指派角色。

### 步驟 5：指派使用者並開始佈建 {#entra-step-5}

1. 開啟應用程式的 **Users and groups** 頁籤，並指派應佈建至 Tuist 的使用者或群組。
2. 返回 **Provisioning** 並啟動它。
3. 檢查 Tuist 的 **成員** 頁籤，確認已指派的使用者出現在組織中。

Entra ID 會依照自己的排程進行佈建，通常每 40 分鐘一次，因此成員不會立即出現。使用 **Provision on demand** 可立即測試單一使用者。

若要測試取消佈建，請在 Entra ID 中取消指派或停用使用者，並確認他們從 Tuist 組織的 **成員** 頁籤中消失。

如果你稍後變更佈建範圍，例如從 **Sync all users and groups** 變更為 **Sync only assigned users and groups**，請隨後點擊 **Restart provisioning**。Entra ID 僅在重新啟動後才會套用新範圍，包括將不再屬於該範圍的使用者取消佈建。

### 指派角色 {#entra-assigning-administrators}

Tuist 有三種 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。若要從 Entra ID 設定這些角色：

1. 在 **App registrations** 中，開啟 Tuist 應用程式，並為你想要指派的每個 Tuist 角色新增應用程式角色。將 **Allowed member types** 設定為 **Users/Groups**，並將 **Value** 設定為 `admin`、`user` 或 `viewer`。
2. 在企業應用程式的 **Users and groups** 頁籤上，為每個使用者或群組指派其中一個應用程式角色。使用者可以擁有多個應用程式角色。Tuist 會套用權限最高的角色，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`，因此屬於對應至不同角色的群組之使用者，將獲得其中最高的角色。
3. 在 **Provisioning > Mappings** 下方，開啟 **Advanced Options** 下拉選單並選擇 **Edit target User attributes**。新增名為 `roles` 的屬性，將 **Type** 設定為 `String`，並勾選 **Multi-Value**。
4. 在 **Provisioning > Mappings > Provision Microsoft Entra ID Users** 下方，點擊 **Add New Mapping**。將 **Mapping type** 設定為 **Expression**，將 **Expression** 設定為 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`，並將 **Target attribute** 設定為你新增的 `roles` 屬性。
5. 保持佈建範圍設定為 **Sync only assigned users and groups**。`AssertiveAppRoleAssignmentsComplex` 與 **Sync all users and groups** 不相容。

`AssertiveAppRoleAssignmentsComplex` 會傳送使用者持有的每個應用程式角色，也會傳送移除動作，因此在 Entra ID 中移除角色會將使用者降級為其仍持有的最高權限角色。`SingleAppRoleAssignment([appRoleAssignments])` 對應至 `roles[primary eq "True"].value` 也可行，但它只會傳送一個角色，且當使用者擁有多個角色時，Entra ID 不保證會選擇哪一個。

在 Entra ID 中變更使用者的應用程式角色，會在下一個佈建週期更新其 Tuist 角色。若使用者在沒有應用程式角色，或使用 `admin`、`user`、`viewer` 以外的值進行佈建，則會獲得組織為單一登入成員設定的註冊角色，除非管理員在 **Settings > Authentication** 下進行了變更，否則該角色為 `user`。

## 生命週期行為 {#lifecycle-behavior}

當你的身分提供者將使用者指派給佈建應用程式時，若 Tuist 尚未知悉該電子郵件，Tuist 會建立該使用者，然後將其加入組織。若該電子郵件已屬於組織外的現有 Tuist 使用者，Tuist 會拒絕該請求，以防止身分提供者主張其未在該組織中管理的使用者。

當你的身分提供者取消指派或停用使用者時，Tuist 會移除其組織角色，同時保留使用者記錄及其擁有的任何工作成果。取消佈建不會全域停用該使用者，因為同一位 Tuist 使用者可能屬於其他組織。

Tuist 公開三個合成 SCIM 群組：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。將成員加入群組會設定其組織角色。從符合其目前角色的群組中移除成員，會將其移回註冊角色，而成員資格本身僅在使用者被取消指派或停用時才會結束。身分提供者也可以透過使用者上的 SCIM `roles` 屬性來設定角色，其值為 `admin`、`user` 或 `viewer`。傳送多個值的身分提供者會取得其中權限最高的角色，其中 `admin` 高於 `user`，而 `user` 高於 `viewer`。

## 支援的 SCIM 功能 {#supported-scim-features}

Tuist 支援身分提供者進行生命週期管理所需的 SCIM 2.0 端點：

- `POST`、`GET`、`PUT`、`PATCH` 和 `DELETE` 用於 `/Users`。
- `GET` 和 `PATCH` 用於 `/Groups`。
- SCIM 探索端點用於 `/ServiceProviderConfig`、`/ResourceTypes` 和 `/Schemas`。
