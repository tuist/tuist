---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 身份验证 {#authentication}

要与服务器交互，CLI
需要使用[承载验证](https://swagger.io/docs/specification/authentication/bearer-authentication/)对请求进行验证。CLI
支持以用户或项目身份进行身份验证。

## 作为用户 {#as-a-user}

在本地计算机上使用 CLI 时，我们建议以用户身份进行身份验证。要以用户身份进行身份验证，需要运行以下命令：

```bash
tuist auth login
```

该命令将引导您完成基于 Web 的身份验证流程。通过身份验证后，CLI 将在`~/.config/tuist/credentials`
下存储一个长期刷新令牌和一个短期访问令牌。该目录中的每个文件都代表您通过身份验证的域，默认情况下应该是`tuist.dev.json`
。该目录中存储的信息比较敏感，因此**务必妥善保管** 。

CLI 在向服务器发出请求时会自动查找凭据。如果访问令牌已过期，CLI 将使用刷新令牌获取新的访问令牌。

## 作为一个项目 {#as-a-project}

在持续集成等非交互式环境中，无法通过交互式流程进行身份验证。对于这些环境，我们建议使用项目范围令牌以项目身份进行身份验证：

```bash
tuist project tokens create
```

CLI 希望将令牌定义为环境变量`TUIST_CONFIG_TOKEN` ，并设置`CI=1` 环境变量。CLI 将使用令牌验证请求。

> [重要] 范围有限 项目范围令牌的权限仅限于我们认为项目可在 CI 环境中安全执行的操作。我们计划将来记录令牌的权限。
