---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 认证{#authentication}

要与服务器交互，CLI
需要使用[承载验证](https://swagger.io/docs/specification/authentication/bearer-authentication/)对请求进行验证。CLI
支持以用户身份、账户身份或使用 OIDC 令牌进行身份验证。

## 作为用户{#as-a-user}

在本地计算机上使用 CLI 时，我们建议以用户身份进行身份验证。要以用户身份进行身份验证，需要运行以下命令：

```bash
tuist auth login
```

该命令将引导您完成基于 Web 的身份验证流程。通过身份验证后，CLI 将在`~/.config/tuist/credentials`
下存储一个长期刷新令牌和一个短期访问令牌。该目录中的每个文件都代表您通过身份验证的域，默认情况下应该是`tuist.dev.json`
。该目录中存储的信息非常敏感，因此**务必妥善保管** 。

CLI 在向服务器发出请求时会自动查找凭据。如果访问令牌已过期，CLI 将使用刷新令牌获取新的访问令牌。

## OIDC 代币{#oidc-tokens}

对于支持 OpenID Connect (OIDC) 的 CI 环境，Tuist 可以自动进行身份验证，而无需管理长期保密信息。在受支持的 CI
环境中运行时，CLI 会自动检测 OIDC 令牌提供者，并将 CI 提供的令牌交换为 Tuist 访问令牌。

### 受支持的 CI 提供商{#supported-ci-providers}

- GitHub 操作
- CircleCI
- Bitrise

### 设置 OIDC 身份验证{#setting-up-oidc-authentication}

1. **将仓库连接到 Tuist**
   ：按照<LocalizedLink href="/guides/integrations/gitforge/github">GitHub 集成指南</LocalizedLink>，将 GitHub 仓库连接到 Tuist 项目。

2. **运行 `tuist auth login`** ：在您的 CI 工作流程中，在任何需要身份验证的命令之前运行`tuist auth login`
   。CLI 将自动检测 CI 环境并使用 OIDC 进行身份验证。

有关特定提供商的配置示例，请参阅<LocalizedLink href="/guides/integrations/continuous-integration">持续集成指南</LocalizedLink>。

### OIDC 令牌范围{#oidc-token-scopes}

OIDC 标记被授予`ci` 范围组，可访问与版本库相连的所有项目。有关`ci` 范围包括哪些内容的详情，请参阅 [范围组](#scope-groups)。

::: tip SECURITY BENEFITS
<!-- -->
OIDC 身份验证比长效令牌更安全，因为
- 没有需要轮换或管理的秘密
- 令牌的有效期很短，且适用于单个工作流运行
- 身份验证与存储库身份绑定
<!-- -->
:::

## 账户令牌{#account-tokens}

对于不支持 OIDC 的 CI 环境，或者需要对权限进行精细控制时，可以使用账户令牌。账户令牌允许你精确指定令牌可以访问哪些作用域和项目。

### 创建账户令牌{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

该命令接受以下选项：

| 选项     | 描述                                                        |
| ------ | --------------------------------------------------------- |
| `--范围` | 必填。以逗号分隔的要授予标记的作用域列表。                                     |
| `--名称` | 必须填写。令牌的唯一标识符（1-32 个字符，仅限字母数字、连字符和下划线）。                   |
| `--到期` | 可选。令牌过期时间。使用格式如`30d` （天）、`6m` （月）或`1y` （年）。如果未指定，则令牌永不过期。 |
| `--项目` | 限制令牌访问特定项目句柄。如果未指定，令牌可访问所有项目。                             |

### 可用范围{#available-scopes}

| 范围                      | 描述                |
| ----------------------- | ----------------- |
| `帐户：成员：已读`              | 阅读账户成员            |
| `帐户：成员：写`               | 管理账户成员            |
| `账户：注册表：读取`             | 从 Swift 软件包注册表中读取 |
| `账户：登记：写`               | 发布到 Swift 软件包注册表  |
| `项目：预览：阅读`              | 下载预览              |
| `项目：预览：写`               | 上传预览              |
| `项目：管理：阅读`              | 读取项目设置            |
| `project:admin:write`   | 管理项目设置            |
| `项目：缓存：读取`              | 下载缓存二进制文件         |
| `项目：缓存：写`               | 上传缓存二进制文件         |
| `project:bundles:read`  | 查看捆绑包             |
| `project:bundles:write` | 上传捆绑包             |
| `项目：测试：读取`              | 阅读测试结果            |
| `project:tests:write`   | 上传测试结果            |
| `项目：构建：读取`              | 阅读构建分析            |
| `项目：构建：编写`              | 上传构建分析            |
| `项目：运行：读取`              | 读取命令运行            |
| `项目：运行：写`               | 创建和更新命令运行         |

### 范围组别{#scope-groups}

作用域组提供了一种方便的方法，可以用一个标识符授予多个相关的作用域。使用作用域组时，它会自动扩展以包含它所包含的所有单独作用域。

| 范围小组 | 包含的瞄准镜                                                                                                                                   |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci` | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 持续集成{#continuous-integration}

对于不支持 OIDC 的 CI 环境，您可以使用`ci` scope group 创建一个账户令牌来验证您的 CI 工作流：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

这将创建一个具有典型 CI 操作（缓存、预览、捆绑包、测试、构建和运行）所需全部作用域的令牌。将生成的令牌作为秘密存储在 CI
环境中，并将其设置为`TUIST_TOKEN` 环境变量。

### 管理账户令牌{#managing-account-tokens}

列出账户的所有令牌：

```bash
tuist account tokens list my-account
```

按名称撤销令牌：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 使用账户令牌{#using-account-tokens}

账户令牌应定义为环境变量`TUIST_TOKEN` ：

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
在需要时使用账户令牌：
- 在不支持 OIDC 的 CI 环境中进行身份验证
- 对令牌可执行的操作进行细粒度控制
- 可访问账户内多个项目的令牌
- 自动过期的限时令牌
<!-- -->
:::
