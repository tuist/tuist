---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO{#sso}

## Google{#google}

如果您有一個 Google Workspace 組織，並希望任何以相同 Google 託管網域名稱登入的開發人員都會加入您的 Tuist
組織，您可以使用下列方式來設定：
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
您必須使用與您要設定網域的組織相關聯的電子郵件，向 Google 進行驗證。
<!-- -->
:::

## Okta{#okta}

使用 Okta 的 SSO 僅適用於企業客戶。如果您有興趣設定，請聯絡我們
[contact@tuist.dev](mailto:contact@tuist.dev)。

在此過程中，我們會指派一位聯絡人幫助您設定 Okta SSO。

首先，您需要建立一個 Okta 應用程式，並將其設定為與 Tuist 搭配使用：
1. 前往 Okta 管理儀表板
2. 應用程式 > 應用程式 > 建立應用程式整合
3. 選擇「OIDC - OpenID Connect」和「Web 應用程式」。
4. 輸入應用程式的顯示名稱，例如「Tuist」。上傳位於 [this
   URL](https://tuist.dev/images/tuist_dashboard.png) 的 Tuist 標誌。
5. 暫時不變登入重定向 URI
6. 在「指定」下選擇所需的 SSO 應用程式存取控制，然後儲存。
7. 儲存後，即可使用應用程式的一般設定。複製「客戶 ID」和「客戶密碼」 - 您需要安全地與您的聯絡人分享。
8. Tuist 團隊需要使用提供的客戶 ID 和密碼重新部署 Tuist 伺服器。這可能需要一個工作日。
9. 伺服器部署完成後，按一下一般設定「編輯」按鈕。
10. 貼上下列重定向 URL：`https://tuist.dev/users/auth/okta/callback`
13. 將「Login initiated by」變更為「Either Okta or App」。
14. 選擇「向使用者顯示應用程式圖示
15. 以`https://tuist.dev/users/auth/okta?organization_id=1` 更新「啟動登入 URL」。`組織_ID`
    將由您的聯絡人提供。
16. 按一下「儲存」。
17. 從您的 Okta 面板啟動 Tuist 登入。
18. 執行以下指令，讓從 Okta 網域簽署的使用者自動存取您的 Tuist 組織：
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
由於 Tuist 目前不支援從您的 Okta 組織自動配置和取消配置使用者，因此使用者一開始需要透過他們的 Okta 面板登入。一旦他們透過 Okta
面板登入，便會自動加入您的 Tuist 組織。
<!-- -->
:::
