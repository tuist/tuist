---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 身份验证{#authentication}

为了与服务器交互，CLI 需要使用 [Bearer
身份验证](https://swagger.io/docs/specification/authentication/bearer-authentication/)
对请求进行身份验证。CLI 支持以用户身份、账户身份或使用 OIDC 令牌进行身份验证。

## 作为用户{#as-a-user}

在本地机器上使用 CLI 时，建议以用户身份进行身份验证。要以用户身份进行身份验证，您需要运行以下命令：

```bash
tuist auth login
```

该命令将引导您完成基于 Web 的身份验证流程。身份验证通过后，CLI
会将一个长期有效的刷新令牌和一个短期有效的访问令牌分别存储在`~/.config/tuist/credentials`
目录下。该目录中的每个文件代表您所验证的域名，默认应为`tuist.dev.json` 。该目录中存储的信息属于敏感信息，因此**请务必妥善保管** 。

CLI 在向服务器发送请求时会自动查询凭据。如果访问令牌已过期，CLI 将使用刷新令牌获取新的访问令牌。

## OIDC 标记{#oidc-tokens}

对于支持 OpenID Connect (OIDC) 的 CI 环境，Tuist 可以自动进行身份验证，而无需您管理长期有效的密钥。在受支持的 CI
环境中运行时，CLI 将自动检测 OIDC 令牌提供商，并将 CI 提供的令牌兑换为 Tuist 访问令牌。

### 支持的 CI 提供商{#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### 配置 OIDC 身份验证{#setting-up-oidc-authentication}

1. **将您的仓库连接到 Tuist**: 请按照
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub
   集成指南</LocalizedLink> 将您的 GitHub 仓库连接到 Tuist 项目。

2. **运行 `tuist auth login`** ：在您的 CI 工作流中，请在任何需要身份验证的命令之前运行`tuist auth login`
   。CLI 将自动检测 CI 环境并通过 OIDC 进行身份验证。

有关特定提供商的配置示例，请参阅
<LocalizedLink href="/guides/integrations/continuous-integration">持续集成指南</LocalizedLink>。

### OIDC 令牌作用域{#oidc-token-scopes}

OIDC 令牌被授予`ci` 作用域组，该作用域组提供对与该仓库关联的所有项目的访问权限。有关`ci` 作用域包含内容的详细信息，请参阅
[作用域组](#scope-groups)。

::: tip SECURITY BENEFITS
<!-- -->
OIDC 认证比长期有效令牌更安全，因为：
- 无需轮换或管理任何秘密
- 令牌存在时间短暂，且作用域仅限于单个工作流运行
- 身份验证与您的仓库身份相关联
<!-- -->
:::

## 账户令牌{#account-tokens}

对于不支持 OIDC 的 CI 环境，或者当您需要对权限进行精细控制时，可以使用账户令牌。账户令牌允许您精确指定令牌可以访问的范围和项目。

### 创建账户令牌{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

该命令支持以下选项：

| 选项           | 描述                                                          |
| ------------ | ----------------------------------------------------------- |
| `--作用域`      | 必填。授予该令牌的范围列表，以逗号分隔。                                        |
| `--name`     | 必填。该令牌的唯一标识符（1-32个字符，仅限字母、数字、连字符和下划线）。                      |
| `--过期`       | 可选。指定令牌的过期时间。格式应为：`30d` （天）、`6m` （月）或`1y` （年）。若未指定，则令牌永不过期。 |
| `--projects` | 将令牌限制为特定的项目句柄。若未指定，该令牌将可访问所有项目。                             |

### 可用作用域{#available-scopes}

| 适用范围                     | 描述              |
| ------------------------ | --------------- |
| `account:members:read`   | 读取账户成员          |
| `account:members:write`  | 管理账户成员          |
| `account:registry:read`  | 从 Swift 包注册表中读取 |
| `account:registry:write` | 发布到 Swift 包注册表  |
| `project:previews:read`  | 下载预览            |
| `project:previews:write` | 上传预览            |
| `project:admin:read`     | 阅读项目设置          |
| `project:admin:write`    | 管理项目设置          |
| `project:cache:read`     | 下载缓存二进制文件       |
| `project:cache:write`    | 上传缓存的二进制文件      |
| `project:bundles:read`   | 查看包             |
| `project:bundles:write`  | 上传包             |
| `project:tests:read`     | 阅读测试结果          |
| `project:tests:write`    | 上传测试结果          |
| `project:builds:read`    | 阅读构建分析          |
| `project:builds:write`   | 上传构建分析数据        |
| `project:runs:read`      | 读取命令运行          |
| `project:runs:write`     | 创建和更新命令运行       |

### 作用域组{#scope-groups}

作用域组提供了一种便捷的方式，可通过单个标识符授予多个相关作用域。使用作用域组时，它会自动展开以包含其包含的所有单独作用域。

| 范围组  | 包含范围                                                                                                                                     |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci` | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 持续集成{#continuous-integration}

对于不支持 OIDC 的 CI 环境，您可以使用`ci` 权限组创建账户令牌，以验证您的 CI 工作流：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

这将生成一个包含典型 CI 操作所需所有作用域（缓存、预览、打包、测试、构建和运行）的令牌。请将生成的令牌作为密钥存储在您的 CI
环境中，并将其设置为`TUIST_TOKEN` 环境变量。

### 管理账户令牌{#managing-account-tokens}

要列出某个账户的所有令牌：

```bash
tuist account tokens list my-account
```

按名称撤销令牌：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 使用账户令牌{#using-account-tokens}

账户令牌应定义为环境变量`TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
在需要时使用账户令牌：
- 在不支持 OIDC 的 CI 环境中的身份验证
- 对令牌可执行的操作进行精细控制
- 一个可在单个账户内访问多个项目的令牌
- 自动过期的限时令牌
<!-- -->
:::
