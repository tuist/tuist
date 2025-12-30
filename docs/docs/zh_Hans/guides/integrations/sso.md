---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO{#sso}

## 谷歌{#google}

如果您有一个 Google Workspace 组织，并希望使用相同的 Google 托管域登录的开发人员添加到您的 Tuist
组织中，您可以使用以下方法进行设置：
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

:: 警告
<!-- -->
您必须使用与您要设置域名的组织绑定的电子邮件在 Google 上进行身份验证。
<!-- -->
:::

## Okta{#okta}

使用 Okta 进行 SSO 仅适用于企业客户。如果您有兴趣设置，请通过
[contact@tuist.dev](mailto:contact@tuist.dev) 联系我们。

在此过程中，我们会为您指定一个联系人，帮助您设置 Okta SSO。

首先，您需要创建一个 Okta 应用程序，并将其配置为与 Tuist 一起使用：
1. 转到 Okta 管理仪表板
2. 应用程序 > 应用程序 > 创建应用程序集成
3. 选择 "OIDC - OpenID Connect "和 "Web 应用程序
4. 输入应用程序的显示名称，例如 "Tuist"。上传位于 [this
   URL](https://tuist.dev/images/tuist_dashboard.png) 的 Tuist 徽标。
5. 登录重定向 URI 暂时保持不变
6. 在 "分配 "下选择所需的 SSO 应用程序访问控制并保存。
7. 保存后，应用程序的常规设置将可用。复制 "客户 ID "和 "客户保密信息"--您需要与联系人安全共享。
8. Tuist 团队需要使用提供的客户端 ID 和秘密重新部署 Tuist 服务器。这可能需要一个工作日。
9. 部署服务器后，单击常规设置 "编辑 "按钮。
10. 粘贴以下重定向 URL：`https://tuist.dev/users/auth/okta/callback`
13. 将 "登录由......发起 "更改为 "Okta 或应用程序"。
14. 选择 "向用户显示应用程序图标
15. 用`https://tuist.dev/users/auth/okta?organization_id=1` 更新 "启动登录 URL"。`组织编号`
    将由联系人提供。
16. 点击 "保存"。
17. 从 Okta 面板启动 Tuist 登录。
18. 运行以下命令，让从 Okta 域签名的用户自动访问 Tuist 组织：
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

:: 警告
<!-- -->
用户最初需要通过 Okta 面板登录，因为 Tuist 目前不支持从您的 Okta 组织自动配置和删除用户。一旦用户通过 Okta 面板登录，他们将被自动添加到
Tuist 组织中。
<!-- -->
:::
