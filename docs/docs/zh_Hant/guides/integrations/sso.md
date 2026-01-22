---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO{#sso}

## Google{#google}

若您擁有 Google Workspace 組織，且希望任何使用相同 Google 主機網域登入的開發人員自動加入您的 Tuist 組織，可透過以下設定實現：
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
您必須使用與所設定組織網域綁定的電子郵件，透過 Google 完成身分驗證。
<!-- -->
:::

## Okta{#okta}

Okta 單一登入服務僅限企業客戶使用。若您有意設定此服務，請透過 [contact@tuist.dev](mailto:contact@tuist.dev)
與我們聯繫。

過程中，您將被指派一位聯絡人協助設定 Okta SSO。

首先，您需要建立一個 Okta 應用程式，並設定使其能與 Tuist 協作：
1. 前往 Okta 管理員儀表板
2. 應用程式 > 應用程式 > 建立應用程式整合
3. 選擇「OIDC - OpenID Connect」與「Web Application」
4. 輸入應用程式的顯示名稱，例如「Tuist」。上傳位於[此網址](https://tuist.dev/images/tuist_dashboard.png)的Tuist標誌。
5. 目前請保留登入重定向 URI 不變
6. 在「指派」項目下選擇所需的 SSO 應用程式存取控制權限，然後儲存設定。
7. 儲存後即可使用應用程式的通用設定。請複製「客戶端識別碼」與「客戶端密鑰」——您需將此資訊安全地分享給您的聯絡窗口。
8. Tuist 團隊需使用提供的客戶端 ID 與密鑰重新部署 Tuist 伺服器。此過程可能耗時最多一個工作天。
9. 伺服器部署完成後，請點擊「一般設定」的「編輯」按鈕。
10. 請貼上以下重定向網址：`https://tuist.dev/users/auth/okta/callback`
13. 將「由...啟動的登入」改為「Okta 或應用程式」。
14. 選擇「向使用者顯示應用程式圖示」
15. 請將「啟動登入網址」更新為：`https://tuist.dev/users/auth/okta?organization_id=1`
    組織識別碼（`）及聯絡窗口（` ）將由您的聯絡人提供。
16. 點擊「儲存」。
17. 請從您的 Okta 儀表板啟動 Tuist 登入程序。
18. 執行以下指令，即可自動授予從您的 Okta 網域簽署的用戶存取您的 Tuist 組織的權限：
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
使用者需先透過其 Okta 儀表板登入，因 Tuist 目前尚未支援從您的 Okta 組織自動增刪使用者權限。當使用者透過 Okta
儀表板登入後，系統將自動將其加入您的 Tuist 組織。
<!-- -->
:::
