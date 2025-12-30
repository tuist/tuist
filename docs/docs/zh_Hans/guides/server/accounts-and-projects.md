---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 账目和项目{#accounts-and-projects}

Tuist 的某些功能需要一个服务器，以增加数据的持久性并与其他服务交互。要与服务器交互，您需要一个账户和一个连接到本地项目的项目。

## 账户{#accounts}

要使用服务器，您需要一个账户。账户有两种类型：

- **个人账户：** 这些账户在注册时自动创建，由身份提供商（如 GitHub）提供的句柄或电子邮件地址的第一部分标识。
- **组织账户：** 这些账户是手动创建的，由开发人员定义的句柄标识。组织允许邀请其他成员参与项目合作。

如果你熟悉 [GitHub](https://github.com)，那么它的概念与之类似，你可以拥有个人账户和组织账户，它们由*句柄* 标识，该句柄用于构建
URL。

::: info CLI-FIRST
<!-- -->
管理账户和项目的大部分操作都是通过 CLI 完成的。我们正在开发一个网络界面，它将使账户和项目管理更加方便。
<!-- -->
:::

您可以通过 <LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink> 下的子命令管理组织。要创建新的组织账户，请运行
```bash
tuist organization create {account-handle}
```

## 项目{#projects}

您的项目，无论是 Tuist 的还是原始 Xcode 的，都需要通过远程项目与您的账户集成。继续与 GitHub
进行比较，这就好比您拥有一个本地和一个远程仓库，您可以在其中推送您的修改。您可以使用
<LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> 来创建和管理项目。

项目由完整句柄标识，完整句柄是组织句柄和项目句柄的连接结果。例如，如果组织句柄为`tuist` ，项目句柄为`tuist`
，则完整句柄为`tuist/tuist` 。

本地项目和远程项目之间的绑定是通过配置文件完成的。如果没有配置文件，请在`Tuist.swift` 上创建，并添加以下内容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
请注意，有些功能（如<LocalizedLink href="/guides/features/cache">二进制缓存</LocalizedLink>）需要您拥有
Tuist 项目。如果您使用的是原始 Xcode 项目，则无法使用这些功能。
<!-- -->
:::

项目的 URL 通过使用完整句柄来构建。例如，Tuist 的仪表板是公开的，可通过
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist) 访问，其中`tuist/tuist`
是项目的完整句柄。
