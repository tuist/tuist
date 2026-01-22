---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 认证{#authentication}

为与服务器交互，命令行界面需通过[承载者认证](https://swagger.io/docs/specification/authentication/bearer-authentication/)对请求进行身份验证。该界面支持以用户身份、账户身份或使用OIDC令牌进行认证。

## 作为用户{#as-a-user}

在本地机器上使用命令行界面时，建议以用户身份进行身份验证。要以用户身份验证，需执行以下命令：

```bash
tuist auth login
```

该命令将引导您完成基于网页的认证流程。认证成功后，CLI将在`~/.config/tuist/credentials`
目录下存储长期刷新令牌和短期访问令牌。该目录中的每个文件代表您认证的域名，默认应为`tuist.dev.json`
。该目录存储的信息属于敏感数据，请务必妥善保管**** 。

CLI 在向服务器发送请求时会自动查找凭据。若访问令牌已过期，CLI 将使用刷新令牌获取新的访问令牌。

## OIDC 令牌{#oidc-tokens}

对于支持OpenID
Connect（OIDC）的CI环境，Tuist可自动完成身份验证，无需您管理长期密钥。在受支持的CI环境中运行时，命令行界面将自动检测OIDC令牌提供商，并将CI提供的令牌兑换为Tuist访问令牌。

### 支持的 CI 提供商{#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### 设置 OIDC 身份验证{#setting-up-oidc-authentication}

1. **将您的仓库连接至 Tuist** ：请遵循
   <LocalizedLink href="/guides/integrations/gitforge/github">GitHub
   集成指南</LocalizedLink> 将您的 GitHub 仓库连接至 Tuist 项目。

2. ** `` 在需要身份验证的命令前，于CI工作流中执行：`tuist auth login`** CLI将自动检测CI环境并通过OIDC进行身份验证。

请参阅<LocalizedLink href="/guides/integrations/continuous-integration">持续集成指南</LocalizedLink>获取供应商特定的配置示例。

### OIDC 令牌作用域{#oidc-token-scopes}

OIDC令牌授予`ci` 范围组，该组可访问与存储库关联的所有项目。有关`ci` 范围的详细信息，请参阅[范围组](#scope-groups)。

::: tip SECURITY BENEFITS
<!-- -->
OIDC认证比长期令牌更安全，因为：
- 无需旋转或管理任何秘密
- 令牌具有短暂生命周期，且作用域限定于单次工作流运行
- 身份验证与您的仓库身份相关联
<!-- -->
:::

## 账户令牌{#account-tokens}

对于不支持 OIDC 的 CI 环境，或需要精细控制权限时，可使用账户令牌。账户令牌允许您精确指定令牌可访问的范围和项目。

### 创建账户令牌{#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

该命令支持以下选项：

| 选项          | 描述                                                       |
| ----------- | -------------------------------------------------------- |
| `--范围`      | 必填项。以逗号分隔的权限范围列表，用于授予令牌权限。                               |
| `--name`    | 必填项。令牌的唯一标识符（1-32个字符，仅限字母数字、连字符和下划线）。                    |
| `--expires` | 可选项。令牌有效期格式示例：`30d` （天制）、`6m` （月制）或`1y` （年制）。未指定时令牌永久有效。 |
| `--项目`      | 将令牌限制为特定项目句柄。若未指定，该令牌将访问所有项目。                            |

### 可用范围{#available-scopes}

| 范围                       | 描述             |
| ------------------------ | -------------- |
| `账户:成员:阅读`               | 阅读账户成员         |
| `账户:成员:写入`               | 管理账户成员         |
| `账户:注册表:读取`              | 从 Swift 包注册表读取 |
| `账户:注册表:写入`              | 发布至Swift软件包注册库 |
| `project:previews:read`  | 下载预览           |
| `project:previews:write` | 上传预览图          |
| `project:admin:read`     | 阅读项目设置         |
| `project:admin:write`    | 管理项目设置         |
| `project:cache:read`     | 下载缓存的二进制文件     |
| `project:cache:write`    | 上传缓存二进制文件      |
| `project:bundles:read`   | 查看捆绑包          |
| `project:bundles:write`  | 上传包            |
| `project:tests:read`     | 阅读测试结果         |
| `project:tests:write`    | 上传测试结果         |
| `project:builds:read`    | 阅读构建分析         |
| `project:builds:write`   | 上传构建分析数据       |
| `project:runs:read`      | 读取命令运行         |
| `project:runs:write`     | 创建和更新命令运行      |

### 作用域组{#scope-groups}

作用域组提供了一种便捷方式，可通过单一标识符授予多个相关作用域。使用作用域组时，它会自动展开包含所有子作用域。

| 范围组  | 包含范围                                                                                                                                     |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `ci` | `project:cache:write`,`project:previews:write`,`project:bundles:write`,`project:tests:write`,`project:builds:write`,`project:runs:write` |

### 持续集成{#continuous-integration}

对于不支持OIDC的CI环境，可创建包含`ci` scope group的账户令牌来认证CI工作流：

```bash
tuist account tokens create my-account --scopes ci --name ci
```

这将生成包含典型CI操作所需全部作用域（缓存、预览、捆绑包、测试、构建和运行）的令牌。请将生成的令牌作为密钥存储在CI环境中，并将其设置为环境变量：`TUIST_TOKEN`
。

### 管理账户令牌{#managing-account-tokens}

要列出账户的所有令牌：

```bash
tuist account tokens list my-account
```

按名称撤销令牌：

```bash
tuist account tokens revoke my-account ci-cache-token
```

### 使用账户令牌{#using-account-tokens}

账户令牌应定义为环境变量：`TUIST_TOKEN`

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
需要时使用账户令牌：
- 在不支持OIDC的CI环境中进行身份验证
- 对令牌可执行的操作进行精细化控制
- 可在账户内访问多个项目的令牌
- 限时令牌会自动过期
<!-- -->
:::
