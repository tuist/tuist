---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 账户与项目 {#accounts-and-projects}

部分 Tuist 功能需要服务器来提供数据持久化并与其他服务交互。要与服务器交互，你需要一个账户，并将你的本地项目关联到一个远程项目。

## 账户 {#accounts}

要使用服务器，你需要一个账户。账户有两种类型：

- **个人账户：** 此类账户在你注册时自动创建，并通过从身份提供商（例如 GitHub）获取或电子邮件地址的第一部分生成的句柄进行标识。
- **组织账户：** 此类账户由开发者手动创建，并通过开发者定义的句柄进行标识。组织允许邀请其他成员协作开发项目。

如果你熟悉 [GitHub](https://github.com)，其概念与之类似：你可以拥有个人和组织账户，它们通过用于构建 URL 的*句柄*进行标识。

> [!NOTE]
> **CLI 优先**
>
> 大多数管理账户和项目的操作都通过 CLI 完成。我们正在开发一个 Web 界面，以便更轻松地管理账户和项目。


你可以通过 <.localized_link href="/cli/organization">`tuist organization`</.localized_link> 下的子命令来管理组织。要创建新的组织账户，请运行：
```bash
tuist organization create {account-handle}
```

### 组织成员资格 {#organization-membership}

用户可以通过邀请、自动单点登录注册或<.localized_link href="/guides/integrations/authentication/scim">跨域身份管理系统配置</.localized_link>成为组织成员。

仅通过组织的身份提供商进行身份验证并不会自动授予成员资格。组织的<.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">单点登录注册策略</.localized_link>决定了来自其受信任域的用户是需要邀请还是可以自动加入。

管理员可以从仪表板或使用 <.localized_link href="/cli/organization/invite">`tuist organization invite`</.localized_link> 邀请成员。传递 `--role admin` 或 `--role viewer` 可在受邀者接受时为其分配除 `user` 之外的角色。

### 角色 {#roles}

每个组织成员都持有以下三种角色之一：

| 角色 | 权限说明 |
| --- | --- |
| **管理员** | 拥有用户的所有权限，并可管理组织：包括成员与邀请、项目、账单、令牌、Webhook 以及设置。 |
| **用户** | 读取并对组织的工作执行操作：运行构建和测试、写入缓存、创建和删除预览，以及更改测试用例的状态。 |
| **查看者** | 仅读取组织的工作内容，不进行任何更改。仪表板、构建、测试运行、不稳定和被隔离的测试、预览、捆绑包以及 Runner 活动均可查看。无法将交互式 Shell 或 VNC 会话附加到 Runner，因为这会在机器上执行命令。 |

在邀请他人时选择角色，之后可以在仪表板的**成员**页面中更改。以这种方式设置的角色不会被后续登录覆盖。

## 项目 {#projects}

你的项目需要通过远程项目与你的账户集成。继续与 GitHub 类比，这就像拥有一个本地仓库和一个远程仓库，你将变更推送到远程仓库。你可以使用 <.localized_link href="/cli/project">`tuist project`</.localized_link> 来创建和管理项目。

项目通过完整句柄进行标识，该句柄由组织句柄和项目句柄拼接而成。例如，如果你的组织句柄为 `tuist`，项目句柄为 `tuist`，则完整句柄为 `tuist/tuist`。

本地项目与远程项目之间的绑定通过配置文件完成。如果尚未创建，请在 `Tuist.swift` 处创建该文件并添加以下内容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

> [!WARNING]
> **仅限 Tuist 项目的功能**
>
> 请注意，某些功能（如<.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link>）需要由 Tuist 管理的项目。如果你未使用 Tuist 管理项目，将无法使用这些功能。


你的项目 URL 通过完整句柄构建。例如，Tuist 的公共仪表板可通过 [tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 访问，其中 `tuist/tuist` 是项目的完整句柄。
