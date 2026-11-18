---
{
  "title": "單一登入",
  "titleTemplate": ":title | 驗證 | 整合 | 指南 | Tuist",
  "description": "了解如何設定單一登入、驗證登入電子郵件網域，以及選擇使用者加入組織的方式。"
}
---
# 單一登入 {#single-sign-on}

Tuist 提供單一登入作為登入選項，為你的組織提供更進階的帳戶安全性。

你可以在組織設定的 **驗證** 頁籤中設定單一登入。支援 Google Workspace、Okta、Microsoft Entra ID，以及自訂的 [OAuth 2.0](https://oauth.net/2/) 提供者。

Microsoft Entra ID 是 OpenID Connect 提供者，Tuist 會根據你的目錄識別碼為你進行設定。本指南針對自訂提供者所述的所有內容（包括登入電子郵件網域驗證與註冊）也同樣適用於它。

> [!NOTE]
> 單一登入控制成員的驗證方式，以及已驗證的使用者是否可以自動加入。<.localized_link href="/guides/integrations/authentication/scim">跨網域身分管理佈建</.localized_link> 控制身分提供者是否能建立、更新及撤銷組織成員。對於 Okta，大多數組織會同時設定這兩者。

## 存取運作方式 {#how-access-works}

提供者身分、登入探索與組織註冊是分開處理的事項：

- **提供者發行者：** 對使用者進行驗證的提供者組織或授權伺服器。Tuist 在查詢已連結的身分時，會結合提供者、發行者與穩定的提供者使用者識別碼。對於 Okta，發行者以 Okta 網域表示。對於 Microsoft Entra ID，則衍生自目錄（租戶）識別碼。對於自訂提供者，則以提供者 URL 表示。
- **登入電子郵件網域：** Tuist 用於從一般登入頁面探索 Okta 或自訂提供者的電子郵件網域。驗證通過後，它也會決定哪些電子郵件地址可被信任，用於新帳戶連結與自動註冊。
- **註冊政策：** 決定來自受信任網域的使用者是否需要邀請，或是可以自動加入。
- **佈建：** 獨立於登入流程之外，建立並管理組織成員資格。

提供者發行者與登入電子郵件網域通常不同。例如，公司可能使用 `example.com` 作為員工電子郵件，而其提供者發行者為 `https://login.vendor.example.net`。新的 Okta 與自訂提供者設定會分別儲存這些值。

### 驗證登入電子郵件網域 {#verify-a-login-email-domain}

Okta 與自訂提供者設定需要先驗證登入電子郵件網域，才能建立新的 Tuist 帳戶，或透過電子郵件地址連結現有帳戶。在網域尚未驗證期間，成員仍可 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">連結其現有帳戶</.localized_link>。

1. 在 **登入電子郵件網域** 中輸入員工電子郵件網域，例如 `example.com`。
2. 儲存單一登入設定。
3. 將 Tuist 顯示的文字記錄新增至該網域的 [域名系統](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) 設定。
4. 返回「驗證」設定，然後點擊 **驗證網域**。

已驗證的登入電子郵件網域只能屬於一個 Tuist 組織。變更網域會清除其驗證狀態，並需要發布新的文字記錄。在網域驗證完成前，自動註冊會保持暫停。

Tuist 每天重新檢查文字記錄。若記錄停止解析，驗證不會立即清除：網域會保留 14 天，且「驗證」設定會顯示 **驗證即將過期**，並附上需要再次發布的記錄。發布記錄並驗證即可清除警告。若 14 天後記錄仍然遺失，網域會恢復為未驗證狀態，提供者探索、身分連結與自動註冊都會停止，直到再次驗證為止。因其他原因導致查詢失敗不會重置計時器，也不會自行清除驗證。在引入每日重新檢查之前已驗證的網域不會被重新檢查。

Google Workspace 不需要這個獨立的 Tuist 驗證步驟，因為 Google 會在已驗證的身分中提供已驗證的 Workspace 網域。

### 選擇註冊政策 {#choose-an-enrollment-policy}

Tuist 支援兩種註冊政策：

- **僅限邀請：** 使用者需要組織邀請。對於 Okta 與自訂提供者，必須先驗證登入電子郵件網域，提供者才能建立全新的 Tuist 帳戶。已收到邀請且擁有現有 Tuist 帳戶的使用者需先接受邀請，然後依照 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">連結現有 Tuist 帳戶</.localized_link> 中的說明連結提供者身分。
- **自動：** 若已驗證的電子郵件符合受信任網域，使用者可以建立或連結帳戶並加入組織，無需邀請。Google 設定使用 Workspace 網域。Okta 與自訂提供者需要已驗證的登入電子郵件網域。

Google 設定預設為自動註冊。新的 Okta 與自訂提供者設定預設為僅限邀請註冊。

**強制單一登入** 設定與註冊無關。存取組織受保護的瀏覽器頁面需要透過其目前的提供者與發行者（或已驗證的 Google Workspace）進行驗證的工作階段。歷史連結身分或透過其他組織提供者進行的驗證並不足夠。一般的 Tuist 登入與其他帳戶的存取仍然可用；強制執行並不會授予組織成員資格。匿名公開儀表板與有時效性的營運支援授權仍保留其各自的存取規則。應用程式預覽頁面僅對組織成員套用強制執行，因此在組織外分享的預覽連結仍可讓原本就能開啟預覽的訪客繼續使用。

當成員的工作階段触及組織時，強制執行即適用：

- **儀表板**：組織的頁面，以及透過 <.localized_link href="/guides/features/agentic-coding/mcp#webmcp">WebMCP</.localized_link> 提供給瀏覽器代理程式的工具，需要使用組織提供者登入的工作階段。
- **Tuist CLI、Tuist 應用程式、MCP 用戶端與 API 參考文件**：為它們登入會建立一個代表成員在所有組織中行動的憑證，因此需要透過強制單一登入的組織進行驗證的工作階段。若成員以其他方式登入，Tuist 會先將其導向提供者，並拒絕使用電子郵件與密碼或 Apple 登入。每當這些用戶端更新其憑證時，Tuist 都會再次檢查。透過組織單一登入取得的憑證會持續更新；先前已透過組織提供者登入過的成員，以其他方式取得的憑證也會持續更新。任何其他憑證（例如在組織強制單一登入前以密碼取得的憑證），會在強制執行下的首次更新後繼續更新四周；之後用戶端會要求成員重新登入。在此期間透過提供者登入（在儀表板或使用 `tuist auth login`）可讓憑證持續更新。

若成員同時屬於多個強制單一登入的組織，則無法登入 CLI、應用程式或 MCP 用戶端，因為一個工作階段只能透過一個組織登入。

### 選擇註冊成員獲得的角色 {#choose-the-enrollment-role}

自動加入的成員會獲得在 **註冊成員角色** 下設定的 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>，預設為 `user`，除非管理員變更。將其設為 `viewer` 可讓目錄中的所有人登入，但不賦予所有人修改內容的權限。

此設定不能設為 `admin`，適用於透過 <.localized_link href="/guides/integrations/authentication/scim">SCIM</.localized_link> 佈建且未指定角色的成員，以及自行登入的成員，且絕不會覆蓋管理員手動設定的角色。

### 連結現有 Tuist 帳戶 {#link-an-existing-account}

已連結的提供者身分會登入整個 Tuist 帳戶，包括該帳戶所屬的其他所有組織。對於 Okta 與自訂提供者，Tuist 僅在電子郵件地址位於已驗證的登入電子郵件網域，或由組織的 SCIM 佈建建立帳戶時，才會自動連結現有帳戶。

不符合條件的帳戶成員需自行連結身分：

1. 使用帳戶慣用的登入方式登入 Tuist。
2. 從身分提供者開啟 Tuist（例如其應用程式圖塊），或在組織強制單一登入時開啟組織的其中一個專案。
3. 確認 Tuist 顯示的組織與身分提供者帳戶，然後點擊 **連結帳戶**。

若在登出狀態下以單一登入開始，系統會要求先登入，之後 Tuist 會回到確認畫面。連結不依賴網域驗證，因此成員可在網域驗證前使用單一登入。

### 現有組織 {#existing-organizations}

所有 Okta 與自訂提供者組織皆使用已驗證網域模型。臨時相容模式已移除。

若您的登入電子郵件網域未經驗證：

- 現有已連結成員可繼續登入，現有的 SSO 強制執行仍適用於組織成員。
- 登入頁面僅透過現有組織成員資格來發現您的提供者。
- 自動註冊已暫停，提供者無法建立新的 Tuist 帳戶，即使有邀請亦然。
- 未連結的成員需登入其現有 Tuist 帳戶並依照上述說明確認連結。由組織 SCIM 佈建建立的帳戶仍可在首次 SSO 登入時進行連結。
- 新註冊使用者不會僅因其電子郵件地址使用您的網域而被要求使用您的提供者。

現有已啟用的註冊與強制執行設定仍會保留，並可關閉。管理員可在網域未經驗證時編輯設定；啟用任一設定都需要驗證。當啟用該設定時，驗證會恢復符合電子郵件地址的自動註冊。Google Workspace 行為不變。

您的 **登入電子郵件網域** 可能已從組織成員處填入。確認該值、發布文字記錄，然後點擊 **驗證網域**。保持記錄發布以供每日重新檢查。

## Google Workspace {#google}

Google Workspace 單一登入會針對 Workspace 網域驗證使用者。管理員可允許相符的使用者自動加入，或要求邀請。

> [!NOTE]
> **必要條件**
>
> 您需要擁有已驗證網域的 Google Workspace 組織。您還必須使用與正在設定的網域綁定的電子郵件透過 Google 進行驗證。

### 設定 {#google-setup}

1. 前往組織的 **驗證** 設定分頁。
2. 啟用單一登入。
3. 選擇 **Google** 作為提供者。
4. 輸入您的 Google Workspace 網域，例如 `example.com`。
5. 選擇 **自動註冊** 或僅限邀請註冊。Google 預設啟用自動註冊。
6. 測試登入流程後，可選擇性啟用 **強制單一登入**。
7. 點擊 **儲存變更**。

## Okta {#okta}

Okta 使用 [OpenID Connect](https://openid.net/developers/how-connect-works/) 驗證成員。Okta 網域識別提供者發行者； separately 驗證的登入電子郵件網域則控制探索、新帳戶連結與註冊。

若您也希望 Okta 自動建立、更新或撤銷成員，請在單一登入運作後設定 <.localized_link href="/guides/integrations/authentication/scim#okta">Okta 跨網域身分管理系統佈建</.localized_link>。

### 步驟 1：建立 Okta 應用程式 {#okta-step-1}

1. 在 Okta 管理儀表板中，前往 **Applications > Applications > Create App Integration**。
2. 選擇 **OpenID Connect** 與 **Web Application**。
3. 設定應用程式名稱，例如 `Tuist`。可選擇性上傳 [Tuist 標誌](https://tuist.dev/images/tuist_dashboard.png)。
4. 將 **登入重新導向 URI** 設為驗證設定頁面上顯示的值，例如 `https://tuist.dev/users/auth/okta/callback`。
5. 在 **Assignments** 下，選擇所需的存取控制並儲存。
6. 從應用程式的一般設定中複製 **Client ID** 與 **Client Secret**。記錄您的 **Okta 網域**，例如 `your-company.okta.com`。
7. 若希望允許從 Okta 儀表板登入，可選擇性點擊一般設定中的 **Edit**，將 **Login initiated by** 變更為 **Either Okta or App**，勾選 **Display application icon to users**，並將 **Initiate login URI** 設為驗證設定頁面上顯示的值。

### 步驟 2：設定 Tuist {#okta-step-2}

1. 前往組織的 **驗證** 設定分頁。
2. 啟用單一登入。
3. 選擇 **Okta** 作為提供者。
4. 輸入 **Okta 網域**、**Client ID** 與 **Client Secret**。
5. 在 **登入電子郵件網域** 下輸入員工電子郵件網域。例如，Okta 網域為 `your-company.okta.com` 時，其登入電子郵件網域可能為 `example.com`。
6. 點擊 **儲存變更**。
7. 將 Tuist 顯示的文字記錄新增至登入電子郵件網域，然後點擊 **驗證網域**。
8. 選擇使用者是否需要邀請或可自動註冊，然後再次儲存設定。
9. 測試登入流程後，可選擇性啟用 **強制單一登入**。

### 步驟 3：將使用者指派給 Okta 應用程式 {#okta-step-3}

指派應允許透過 Okta 應用程式進行驗證的使用者或群組。

指派會授予登入流程的存取權，但組織成員資格仍遵循註冊政策。若相同的使用者是透過跨網域身分管理系統進行佈建，Tuist 會在使用者首次登入時，將 Okta 身分連結至 SCIM 建立的帳戶。若成員帳戶在 SCIM 加入前已存在，則當其電子郵件地址位於已驗證的登入電子郵件網域中，或從已登入的帳戶確認連結後，就會完成連結。

## Microsoft Entra ID {#microsoft-entra-id}

Microsoft Entra ID 透過 [OpenID Connect](https://openid.net/developers/how-connect-works/) 驗證成員。Tuist 會從您的目錄（租用戶）識別碼衍生授權、權杖與使用者資訊端點，因此您只需輸入該值以及應用程式憑證。

若您也希望 Entra ID 自動建立、更新或撤銷成員，請在單一登入運作後設定 <.localized_link href="/guides/integrations/authentication/scim#microsoft-entra-id">Microsoft Entra ID 跨網域身分管理系統佈建</.localized_link>。

### 步驟 1：註冊 Entra 應用程式 {#entra-step-1}

1. 在 [Microsoft Entra admin center](https://entra.microsoft.com) 中，前往 **Identity > Applications > App registrations > New registration**。
2. 設定應用程式名稱，例如 `Tuist`。
3. 在 **Redirect URI** 下，選擇 **Web** 平台，並輸入驗證設定頁面上顯示的值，例如 `https://tuist.dev/users/auth/oauth2/callback`。
4. 註冊應用程式，然後從其概覽頁面複製 **Directory (tenant) ID** 與 **Application (client) ID**。
5. 前往 **Certificates & secrets > New client secret**，建立秘密金鑰並複製其 **Value**。Microsoft 僅顯示一次該值，且每個客戶端秘密金鑰都有到期日，因此請記錄需要輪換的時間。
6. 前往 **API permissions**，並確認已授予委派的 Microsoft Graph 權限 `openid`、`profile` 與 `email`。
7. 若希望讓成員從 My Apps 入口網站啟動登入流程，可選擇性將 **Branding & properties** 下的 **Home page URL** 設為驗證設定頁面上顯示的值。

### 步驟 2：設定 Tuist {#entra-step-2}

1. 前往組織的 **驗證** 設定分頁。
2. 啟用單一登入。
3. 選擇 **Microsoft Entra ID** 作為提供者。
4. 輸入 **Directory (tenant) ID**、**Client ID** 與 **Client Secret**。
5. 在 **登入電子郵件網域** 下輸入員工電子郵件網域。例如，使用者以 `first.last@example.com` 形式登入的目錄，其登入電子郵件網域為 `example.com`。
6. 點擊 **儲存變更**。
7. 將 Tuist 顯示的文字記錄新增至登入電子郵件網域，然後點擊 **驗證網域**。
8. 選擇使用者是否需要邀請或可自動註冊，然後再次儲存設定。
9. 測試登入流程後，可選擇性啟用 **強制單一登入**。

### 步驟 3：將使用者指派給 Entra 應用程式 {#entra-step-3}

指派應允許驗證的使用者或群組。若應用程式設定為需要指派，則只有已指派的使用者可以登入。

指派可授予存取登入流程的權限，但組織成員資格仍遵循註冊政策。若相同的使用者是透過跨網域身分管理系統佈建，Tuist 會在使用者首次登入時，將 Entra 身分連結至 SCIM 建立的帳戶。若成員的帳戶在 SCIM 新增之前就已存在，則當其電子郵件地址位於已驗證的登入電子郵件網域，或從已登入的帳戶確認連結後，才會進行連結。

### 電子郵件聲明需求 {#entra-email-claim}

Tuist 會從 Microsoft Graph 使用者資訊端點讀取已驗證使用者的個人資料，該端點僅在使用者有可用的電子郵件地址時才會回傳。若目錄使用者的 `mail` 屬性為空，則無法登入，因為 Tuist 沒有可用來比對登入電子郵件網域的地址。

在推出單一登入之前，請確認您指派的使用者在目錄中已填入電子郵件地址。從內部部署 Active Directory 同步且沒有信箱的使用者，是最常缺少此屬性的情況。

### 條件式存取與多因素驗證 {#entra-conditional-access}

條件式存取政策、多因素驗證與登入風險政策會以與其他 Entra 應用程式相同的方式套用於 Tuist 應用程式，因為它們會在授權請求期間進行評估。不需要額外的 Tuist 設定。

## 自訂 OAuth 2.0 提供者 {#custom-oauth-2-provider}

自訂 OAuth 2.0 提供者允許組織使用 Google Workspace 或 Okta 以外的身分服務。提供者的使用者資訊端點必須回傳穩定的使用者識別碼與電子郵件地址。

1. 在提供者中，建立 OAuth 2.0 Web 應用程式。
2. 將 **Sign-in redirect URI** 與可選的 **Initiate login URI** 設為 Tuist 驗證設定中顯示的值。
3. 在 Tuist 中，啟用單一登入並選擇 **OAuth2**。
4. 輸入提供者 URL、授權端點、權杖端點、使用者資訊端點、客戶端識別碼與客戶端秘密金鑰。
5. 輸入並儲存 **登入電子郵件網域**。這是員工電子郵件網域，而非提供者 URL。
6. 將 Tuist 顯示的文字記錄新增至登入電子郵件網域，然後點擊 **驗證網域**。
7. 選擇僅限邀請或自動註冊，並儲存設定。
8. 在選擇性啟用 **強制單一登入** 之前測試登入。

提供者 URL 將身分範圍限定於發行的提供者。已驗證的登入電子郵件網域決定 Tuist 在連結或註冊使用者時可信任哪些電子郵件地址。

## 命令列設定 {#command-line-configuration}

命令列介面可以設定 Google Workspace 或 Okta 並選擇註冊政策。例如：

```bash
tuist organization update sso example \
  --provider okta \
  --organization-id your-company.okta.com \
  --enrollment-policy invitation-only
```

Microsoft Entra ID 與自訂提供者是從組織的驗證設定進行設定，而非從命令列。

`--organization-id` 值用於識別提供者組織。它不是登入電子郵件網域。在註冊新的 Okta 使用者之前，請從組織的驗證設定中新增並驗證登入電子郵件網域。

## 疑難排解 {#troubleshooting}

### 現有成員可以登入，但新使用者無法登入 {#existing-members-can-sign-in-but-new-users-cannot}

對於 Okta 與自訂提供者設定，請確認登入電子郵件網域已驗證。然後邀請使用者或啟用自動註冊。

### 單一登入要求您先登入 {#single-sign-on-asks-you-to-log-in-first}

您的 Tuist 帳戶電子郵件地址不在組織已驗證的登入電子郵件網域上，或該網域尚未驗證，因此 Tuist 不會自動連結提供者身分。請使用您慣用的登入方法登入並確認連結，如 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">連結現有的 Tuist 帳戶</.localized_link> 所述。
### Tuist 找不到電子郵件地址對應的組織 {#tuist-cannot-find-an-organization-for-an-email-address}

確認使用者輸入了預期的員工電子郵件地址，且其網域與已驗證的登入電子郵件網域完全相符。現有成員也可能透過其目前的組織成員資格被發現。

### 網域驗證仍在待處理中 {#domain-verification-remains-pending}

確認文字記錄名稱與值與 Tuist 顯示的值完全相符。網域名稱系統變更可能需要時間傳播，因此在記錄公開可用後重試驗證。

### 變更提供者後登入停止 {#sign-in-stopped-after-changing-the-provider}

確認新的提供者設定、驗證登入電子郵件網域，並在啟用強制執行之前測試登入流程。
