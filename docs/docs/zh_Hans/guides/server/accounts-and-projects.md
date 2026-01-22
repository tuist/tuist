---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# 账户与项目{#accounts-and-projects}

某些 Tuist 功能需要服务器支持，该服务器可实现数据持久化并能与其他服务交互。要与服务器交互，您需要一个账户以及一个与本地项目关联的项目。

## 账户{#accounts}

使用本服务器需注册账户。账户分为两种类型：

- **个人账户：** 这些账户在注册时自动创建，通过身份提供商（如GitHub）获取的用户名或电子邮件地址的前缀进行标识。
- **组织账户：** 这些账户由开发者手动创建，通过其定义的标识符进行识别。组织功能允许邀请其他成员共同协作项目。

若您熟悉[GitHub](https://github.com)，其概念与此类似：用户可拥有个人账户和组织账户，这些账户通过*用户名（如*
）进行标识，该用户名用于构建URL。

::: info CLI-FIRST
<!-- -->
管理账户和项目的大部分操作均通过命令行界面（CLI）完成。我们正在开发一个网页界面，届时将更便捷地管理账户和项目。
<!-- -->
:::

可通过以下子命令管理组织：`tuist organization`</LocalizedLink>创建新组织账户请执行：
```bash
tuist organization create {account-handle}
```

## 项目{#projects}

无论是Tuist还是原始Xcode的项目，都需要通过远程项目与您的账户集成。延续与GitHub的类比，这相当于拥有本地和远程仓库来推送更改。您可使用
<LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> 创建和管理项目。

项目通过完整句柄进行标识，该句柄由组织句柄与项目句柄拼接而成。例如：若组织句柄为`tuist` ，项目句柄为`tuist`
，则完整句柄为`tuist/tuist` 。

本地项目与远程项目的绑定通过配置文件实现。若未创建，请在以下路径创建：`Tuist.swift` 并添加以下内容：

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
请注意，某些功能（如<LocalizedLink href="/guides/features/cache">二进制缓存</LocalizedLink>）需要您拥有Tuist项目。若使用原始Xcode项目，则无法使用这些功能。
<!-- -->
:::

项目网址由完整项目标识符构成。例如，Tuist的公共仪表盘可通过[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist)访问，其中`tuist/tuist`
即为该项目的完整标识符。
