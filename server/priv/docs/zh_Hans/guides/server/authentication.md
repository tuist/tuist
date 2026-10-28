---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# 身份验证 {#authentication}

要与服务器交互，CLI 需要使用 [Bearer 身份验证](https://swagger.io/docs/specification/authentication/bearer-authentication/) 对请求进行身份验证。CLI 支持以用户身份、以账户身份或使用 OIDC 令牌进行身份验证。

## 以用户身份 {#as-a-user}

在本地机器上使用 CLI 时，我们建议以用户身份进行身份验证。要以用户身份进行身份验证，你需要运行以下命令：

```bash
tuist auth login
```

该命令将引导你完成基于 Web 的身份验证流程。身份验证成功后，CLI 会将长期有效的刷新令牌和短期有效的访问令牌存储在 `~/.config/tuist/credentials` 下。目录中的每个文件代表你进行身份验证的域，默认情况下应为 `tuist.dev.json`。存储在该目录中的信息是敏感信息，因此 **请务必妥善保管**。

CLI 在向服务器发出请求时会自动查找凭据。如果访问令牌已过期，CLI 将使用刷新令牌获取新的访问令牌。

> [!NOTE]
> 如果你的组织使用单点登录，请在浏览器中选择企业登录选项并输入你的工作电子邮件地址。Tuist 可以根据你现有的组织成员资格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已验证的登录电子邮件域</.localized_link> 找到提供商。

## OIDC 令牌 {#oidc-tokens}

对于支持 OpenID Connect (OIDC) 的 CI 环境，Tuist 可以自动进行身份验证，而无需你管理长期有效的密钥。在受支持的 CI 环境中运行时，CLI 将自动检测 OIDC 令牌提供商，并将 CI 提供的令牌交换为 Tuist 访问令牌。

### 支持的提供商 {#supported-ci-providers}

Tuist 识别这些 CI 提供商，并通过你的仓库连接将其令牌映射到项目：

- GitHub Actions
- CircleCI
- Bitrise

任何其他颁发 OpenID Connect 令牌的身份提供商都可以通过 [工作负载身份信任策略](#workload-identity-trust-policies) 进行身份验证，你只需为账户中的所有当前和未来项目配置一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 设置 OIDC 身份验证 {#setting-up-oidc-authentication}

对于 GitHub Actions、CircleCI 和 Bitrise：

1. **将你的仓库连接到 Tuist**：按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 集成指南</.localized_link> 将你的 GitHub 仓库连接到你的 Tuist 项目。

2. **运行 `tuist auth login`**：在你的 CI 工作流中，在任何需要身份验证的命令之前运行 `tuist auth login`。CLI 将自动检测 CI 环境并使用 OIDC 进行身份验证。

请参阅 <.localized_link href="/guides/integrations/continuous-integration">持续集成指南</.localized_link> 以获取特定于提供商的配置示例。

### 工作负载身份信任策略 {#workload-identity-trust-policies}

信任策略允许来自其他身份提供商（例如部署平台、Kubernetes 集群或自管理的 CI 系统）的工作负载在没有长期有效的 Tuist 密钥的情况下访问项目。提供商必须：

- 可通过公共地址上的 HTTPS 访问。Tuist 不遵循重定向，也不连接到私有或内部网络地址，包括来自自托管 Tuist 服务器的地址。
- 颁发使用非对称密钥签名的 JWT，例如 `RS256` 或 `ES256`。未签名的令牌和使用共享密钥签名的令牌（`HS256` 及类似方式）将被拒绝。
- 在固定的 HTTPS URL 上以 JSON Web Key Set (JWKS) 形式发布其签名密钥。响应大小不得超过 64 KiB，且最多包含 20 个密钥。
- 在每个令牌中包含过期时间 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 颁发者保留用于上述基于仓库的流程，不能在信任策略中使用。

> [!NOTE]
> 对于自托管部署，在配置工作负载身份或将作业迁移到它们之前，请应用数据库迁移并升级每个正在服务的 Tuist 服务器副本。然后将 CLI 或 Elixir 集成升级到支持 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。现有的 GitHub Actions、CircleCI 和 Bitrise 作业继续使用基于仓库的授权，不需要账户句柄。在切换生产作业之前，请使用预期的工作负载验证短期令牌交换和缓存操作。要停止新的交换，请删除策略；允许已颁发的 Tuist 访问令牌最多在一小时内过期。删除策略不会立即撤销这些令牌。

#### 创建策略 {#create-a-trust-policy}

在 Tuist 仪表板中，打开你账户的 **设置** > **身份验证**，找到 **工作负载身份** 部分。你必须是账户管理员（或个人账户的所有者）。每个账户最多可以有 20 个策略。配置一次身份以获得账户范围的 CI 访问权限；无需选择项目。

使用 **工作负载身份** 旁边的开关打开策略表单。当账户有已保存的身份时，开关初始状态为开启，并在保存后保持开启。对于没有身份的账户，开关初始状态为关闭。对于组织，该部分显示在 **SCIM 预配** 下方。隐藏表单会保留你的草稿，并且不会禁用工作负载身份验证：已保存身份的卡片和设置文档链接仍然可见。每张卡片显示身份的名称、颁发者和 JWKS URL、受众、确切的 JSON 声明、账户范围以及创建时间。使用卡片上的操作删除身份。

选择 **自定义提供商** 以输入以下字段，或选择 **Fly.io Machines** 以根据你的组织 slug 以及数字化的组织和应用程序 ID 生成它们。Fly 模板使生成的颁发者、JWKS URL 和声明在 **高级配置** 下可编辑。更改模板或辅助值会保留你手动编辑的字段。如果你的颁发者、JWKS URL 或声明覆盖了模板，Tuist 会展开 **高级配置** 并显示警告，以便你可以审查将要保存的策略。切换回 **自定义提供商** 以在没有 Fly 辅助工具的情况下继续。模板仅填充配置，不会改变 Tuist 验证令牌的方式。

| 字段 | 描述 |
| --- | --- |
| 名称 | 用于识别策略的标签，在账户内唯一。 |
| 颁发者 URL | 令牌的 `iss` 声明。它必须完全匹配，包括任何尾部斜杠。 |
| JWKS URL | 提供商签名密钥的 HTTPS URL。Tuist 直接使用此 URL，不读取提供商的 OpenID Connect 发现文档，因此请从提供商的文档或 `<issuer>/.well-known/openid-configuration` 中复制 `jwks_uri`。 |
| 受众 | 令牌必须为其颁发的受众，默认为 `tuist`。令牌的 `aud` 必须等于它，或者当 `aud` 是列表时包含它。使用仅 Tuist 接受的值，以便为其他服务铸造的令牌不能在此处重放。 |
| 声明 | 一个包含 1 到 10 个令牌必须包含的声明的 JSON 对象，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 输入限制为 8 KiB。值必须是字符串、有符号 64 位整数或布尔值，并且必须完全匹配，包括其类型：`"123"` 与 `123` 不匹配。不允许嵌套对象、列表以及时间或令牌声明，如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每个策略授予对 **账户拥有的所有当前和未来项目** 的 CI 访问权限，无需选择单个项目。你可以在创建第一个项目之前配置身份。这不会授予账户管理权限或对其他账户的访问权限。

每个能够获取具有匹配声明的令牌的工作负载都可以访问所有这些项目，因此请选择提供商保证且无人可以重用的声明。优先使用稳定的数字 ID，而不是可以在删除后重命名或重新注册的名称。

> [!WARNING]
> 在共享身份提供商上，将策略绑定到你的组织或租户 **以及** 预期的应用程序、项目或服务账户。诸如 `main` 之类的分支名称、诸如 `production` 之类的环境或单独的通用角色不是身份边界：另一个租户可能获得具有相同值的令牌。例如，GitLab.com 策略必须包括预期项目的稳定 `project_id`，而不仅仅是 `ref`。匹配的令牌授予账户范围的 CI 访问权限，包括缓存写入，因此信任无关工作负载的策略可能导致缓存投毒。

Tuist 仅在检查颁发者、受众、过期时间、不早于时间（最多 60 秒的时钟偏差）和每个声明后，才授予对其自身 JWKS URL 持有签署令牌密钥的策略的访问权限。颁发的一小时 CI 令牌是账户范围的，不是项目 ID 的快照：它包括颁发后创建或转移到账户中的项目。项目授权仍然需要当前的账户所有权，因此将项目转出会移除该账户令牌下的访问权限。

#### 验证工作负载 {#authenticate-a-workload}

1. 从你的提供商请求具有策略受众的身份令牌。
2. 将 `TUIST_OIDC_TOKEN` 设置为该令牌，并将 `TUIST_OIDC_ACCOUNT` 设置为拥有项目的 Tuist 账户句柄。每次信任策略交换都需要账户。它仅选择查找位置，本身不授予任何权限。
3. 运行 `tuist auth login`。对于 Elixir 项目，你可以使用 `mix tuist.login`，或者在没有 `TUIST_TOKEN` 或有效存储的凭据时让 Elixir 集成自动交换令牌。

生成的 Tuist 访问令牌仅具有 `ci` 范围组，并涵盖所选账户拥有的所有当前和未来项目。如果账户中有超过 20 个策略匹配同一令牌，或者它们使用超过两个不同的 JWKS URL，则交换失败。

Tuist 不刷新这些会话。访问令牌在一小时后过期，且没有刷新令牌。提供商身份令牌通常仅有效几分钟，因此保留旧的 `TUIST_OIDC_TOKEN` 不是续订策略：对于运行时间超过一小时的任务，请在 Tuist 会话过期前请求新的身份令牌并再次登录。移除策略会停止新的交换，但已颁发的访问令牌在过期前仍然有效。

Tuist 在专用且大小受限的缓存中缓存提供商的签名密钥，成功获取后最多缓存 15 分钟。条目可能会更早被驱逐并再次获取。失败的获取不会被缓存。如果你的提供商轮换密钥，它应在使用该密钥签署令牌前至少 15 分钟在其 JWKS 中发布新密钥，因为使用不在缓存集中的密钥签署的令牌将被拒绝，直到缓存过期。只有在 JWKS 包含单个符合条件的签名密钥时，才接受没有密钥 ID (`kid`) 的令牌。当 JWKS 中存在密钥 ID 时，它必须是长度不超过 256 字节的字符串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是通用令牌输入，不是绕过服务器信任的方法。它优先于 CI 提供商检测，服务器仍然只接受内置提供商和具有匹配信任策略的身份。不要将身份令牌放入 `TUIST_TOKEN`，后者期望的是 Tuist 凭据。

如果交换失败，请检查策略中的颁发者、受众和每个声明是否与令牌完全匹配，JWKS URL 是否提供签署令牌的密钥，策略是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否命名了拥有项目的账户。为了避免暴露哪些身份受信任，Tuist 对所有这些情况返回相同的错误。

### Fly.io Machines {#flyio-machines}

[Fly.io 支持 OIDC 工作负载身份](https://docs.fly.io/reference/openid-connect/)。Machine 可以从其本地 `/.fly/api` Unix 套接字请求短期的签名身份令牌，无需 Fly API 令牌或长期的 Tuist 秘密。Fly 令牌标识组织和应用程序，而不是源代码仓库，因此请使用信任策略而不是连接 GitHub 仓库：

1. 从在你的 Fly Machine 内部颁发的身份令牌中获取颁发者 (`iss`)、组织 ID (`org_id`) 和应用程序 ID (`app_id`)。颁发者是 `https://oidc.fly.io/<organization-slug>`。使用数字 ID，而不是组织或应用程序名称。
2. 使用 **Fly.io Machines** 模板 [创建信任策略](#create-a-trust-policy)，并输入组织 slug 和两个数字 ID。它会填充下面的值并将 ID 保持为字符串。你也可以使用 **自定义提供商** 手动输入它们；在声明中保留 ID 周围的引号。

   | 字段 | 值 |
   | --- | --- |
   | 颁发者 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | 受众 | `tuist` |
   | 声明 | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 内部，将 `TUIST_OIDC_ACCOUNT` 设置为拥有项目的 Tuist 账户句柄（不是 Fly 组织 slug），请求受众为 `tuist` 的令牌，并使用 `TUIST_OIDC_TOKEN` 将其传递给 `tuist auth login`：

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

对于初始设置，你可以在导出令牌后、取消设置之前，仅在本地检查身份字段。这会解码声明以进行配置；Tuist 在身份验证期间会单独验证签名：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要打印或提交令牌本身。授权 Fly 应用中的每个 Machine 都可以对 Tuist 账户中的所有当前和未来项目进行身份验证。为每个额外的应用创建单独的策略。Fly 身份令牌大约十分钟后过期，因此在长时间运行的 Machine 上，请在一小时 Tuist 会话过期之前请求新令牌并再次运行 `tuist auth login`。

### OIDC 令牌作用域 {#oidc-token-scopes}

OIDC 令牌被授予 `ci` 作用域组。对于 GitHub Actions、CircleCI 和 Bitrise，这提供了对所有连接到仓库的项目的访问权限。对于工作负载身份信任策略，这提供了对所选账户拥有的所有当前和未来项目的访问权限，而不授予项目创建、项目管理、Runner 管理或账户成员管理权限。有关 `ci` 作用域包含的内容的详细信息，请参阅 [作用域组](#scope-groups)。

> [!TIP]
> **安全优势**
>
> OIDC 身份验证比长期令牌更安全，因为：
> - 无需轮换或管理秘密
> - 令牌是短期的
> - 身份验证与你的仓库身份或显式授权的工作负载身份绑定


## Gradle 插件身份验证 {#gradle-plugin-authentication}

Gradle 插件使用 Tuist CLI 身份验证状态，不定义单独的登录流程。使用 CLI 进行一次身份验证，插件将重用这些凭据。

对于项目和服务器配置，包括 `project` 和 `url`，请使用规范的 <.localized_link href="/references/tuist-toml">tuist.toml 参考</.localized_link>。

对于本地使用，请运行：

```bash
tuist auth login
```

对于 CI，请使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 身份验证</.localized_link>（推荐在可用时使用）
- <.localized_link href="/guides/server/authentication#continuous-integration">账户令牌身份验证</.localized_link>通过 `TUIST_TOKEN`

对于自托管的 Tuist 服务器，请在 `tuist.toml` 中定义服务器 URL（例如 `url = "https://tuist.your-company.com"`）并运行标准登录流程。URL 从插件使用的同一配置文件中解析。

配置身份验证后，正常运行你的 Gradle 缓存命令和任务。

## 账户令牌 {#account-tokens}

对于不支持 OIDC 的 CI 环境，或者当你需要对权限进行细粒度控制时，可以使用账户令牌。账户令牌允许你精确指定令牌可以访问的作用域和项目。

### 创建账户令牌 {#creating-an-account-token}

创建账户令牌的最简单方法是从仪表板：

1. 在 Tuist 仪表板中打开组织。
2. 转到 **设置** > **令牌**。
3. 选择 **生成令牌**。
4. 选择名称、可选的过期时间、项目访问权限以及令牌所需的作用域。
5. 在关闭对话框之前复制生成的令牌值。令牌值仅显示一次。

你也可以从 CLI 创建账户令牌，这对于脚本编写或自动化很有用：

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> 将 `account-handle` 替换为拥有你想要令牌访问的项目的账户句柄。这可以是组织账户，不一定是你的个人账户。

该命令接受以下选项：

| 选项 | 描述 |
| --- | --- |
| `--scopes` | 必需。要授予令牌的作用域的逗号分隔列表。 |
| `--name` | 必需。令牌的唯一标识符（1-32 个字符，仅限字母数字、连字符和下划线）。 |
| `--expires` | 可选。令牌应过期的时间。使用如 `30d`（天）、`6m`（月）或 `1y`（年）的格式。如果未指定，令牌永不过期。 |
| `--projects` | 将令牌限制为特定的项目句柄。如果未指定，令牌可以访问所有项目。 |

### 可用作用域 {#available-scopes}

| 作用域 | 描述 |
| --- | --- |
| `account:cache:read` | 下载账户范围的缓存二进制文件 |
| `account:cache:write` | 上传账户范围的缓存二进制文件 |
| `account:members:read` | 读取账户成员 |
| `account:members:write` | 管理账户成员 |
| `account:registry:read` | 从 Swift 包注册表读取 |
| `account:registry:write` | 发布到 Swift 包注册表 |
| `account:runners:read` | 读取 Runner 作业、工作流、配置文件和卷 |
| `account:runners:write` | 管理 Runner 配置文件并清除 Runner 卷 |
| `project:previews:read` | 下载预览 |
| `project:previews:write` | 上传预览 |
| `project:admin:read` | 读取项目及其设置 |
| `project:admin:write` | 创建、更新和删除项目。创建项目需要具有访问所有项目权限的令牌 |
| `project:cache:read` | 下载缓存的二进制文件 |
| `project:cache:write` | 上传缓存的二进制文件 |
| `project:bundles:read` | 查看捆绑包 |
| `project:bundles:write` | 上传捆绑包 |
| `project:tests:read` | 读取测试结果 |
| `project:tests:write` | 上传测试结果 |
| `project:builds:read` | 读取构建分析数据 |
| `project:builds:write` | 上传构建分析数据 |
| `project:runs:read` | 读取命令运行记录 |
| `project:runs:write` | 创建和更新命令运行记录 |

### 作用域组 {#scope-groups}

作用域组提供了一种便捷的方式，通过单个标识符授予多个相关作用域。当你使用作用域组时，它会自动扩展以包含其包含的所有单独作用域。

| 作用域组 | 包含的作用域 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持续集成 {#continuous-integration}

对于不支持 OIDC 的 CI 环境，请使用 `ci` 作用域组创建账户令牌以验证你的 CI 工作流。在仪表板中生成令牌时，选择 **CI** 预设。

你也可以从 CLI 创建相同的令牌：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

这将创建一个具有典型 CI 操作所需的所有作用域的令牌（缓存、预览、捆绑包、测试、构建和运行）。将生成的令牌作为机密存储在 CI 环境中，并将其设置为 `TUIST_TOKEN` 环境变量。

### 管理账户令牌 {#managing-account-tokens}

在账户仪表板中打开 **设置** > **令牌**，以查看账户令牌、检查令牌的作用域和项目访问权限，以及在轮换期间撤销令牌。

列出账户的所有令牌：

```bash
tuist account tokens list account-handle
```

按名称撤销令牌：

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### 使用账户令牌 {#using-account-tokens}

账户令牌应定义为环境变量 `TUIST_TOKEN`：

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **何时使用账户令牌**
>
> 在以下情况下使用账户令牌：
> - 在不支持 OIDC 的 CI 环境中进行身份验证
> - 对令牌可以执行的操作进行细粒度控制
> - 一个可以访问账户内多个项目的令牌
> - 具有自动过期功能的限时令牌
