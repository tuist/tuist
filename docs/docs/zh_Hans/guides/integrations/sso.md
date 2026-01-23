---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO{#sso}

## Google{#google}

若您拥有 Google Workspace 组织，且希望任何使用相同 Google 托管域登录的开发者自动加入您的 Tuist 组织，可通过以下方式设置：
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

:: 警告
<!-- -->
您必须使用与所设置组织域名关联的邮箱通过Google进行身份验证。
<!-- -->
:::

## Okta{#okta}

Okta单点登录仅面向企业客户开放。如需配置该服务，请通过[contact@tuist.dev](mailto:contact@tuist.dev)联系我们。

在此过程中，您将被分配一名联系人协助设置Okta单点登录。

首先，您需要创建一个Okta应用程序，并将其配置为与Tuist协同工作：
1. 前往 Okta 管理控制台
2. 应用程序 > 应用程序 > 创建应用程序集成
3. 选择"OIDC - OpenID Connect"和"Web Application"
4. 输入应用程序的显示名称，例如"Tuist"。上传位于[此网址](https://tuist.dev/images/tuist_dashboard.png)的Tuist徽标。
5. 当前请保留登录重定向URI原样
6. 在"任务"下选择所需的SSO应用访问控制权限并保存。
7. 保存后将显示应用程序的通用设置。复制"客户端ID"和"客户端密钥"。同时记录您的Okta组织URL（例如：`https://your-company.okta.com`
   ），您需要将这些信息安全地分享给您的对接联系人。
8. 当 Tuist 团队完成 SSO 配置后，请点击"常规设置"中的"编辑"按钮。
9. 粘贴以下重定向网址：`https://tuist.dev/users/auth/okta/callback`
10. 将"Login initiated by"改为"Okta 或 应用程序"。
11. 选择"向用户显示应用程序图标"
12. 将"登录启动URL"更新为：`https://tuist.dev/users/auth/okta?organization_id=1`
    。`中的organization_id（` ）将由您的对接人提供。
13. 点击"保存"。
14. 请通过您的Okta控制台启动Tuist登录流程。

:: 警告
<!-- -->
用户需先通过Okta控制台登录，因Tuist目前不支持从Okta组织自动创建或注销用户。用户通过Okta控制台登录后，将自动加入您的Tuist组织。
<!-- -->
:::
