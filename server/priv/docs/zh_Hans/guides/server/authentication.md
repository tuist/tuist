---
{
  "title": "身份验证",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "了解如何通过 CLI 向 Tuist 服务器进行身份验证。"
}
---
# 身份验证 {#authentication}

要与服务器交互，CLI 需要使用 [Bearer 身份验证](https://swagger.io/docs/specification/authentication/bearer-authentication/) 对请求进行身份验证。CLI 支持以用户身份、以账户身份或使用 OIDC 令牌进行身份验证。

## 以用户身份 {#as-a-user}

在本地机器上使用 CLI 时，我们建议以用户身份进行身份验证。要以用户身份进行身份验证，你需要运行以下命令：

```bash
tuist auth login
```

该命令将引导你完成基于网页的身份验证流程。身份验证成功后，CLI 会将长期有效的刷新令牌和短期有效的访问令牌存储在 `~/.config/tuist/credentials` 下。目录中的每个文件代表你进行身份验证的域，默认情况下应为 `tuist.dev.json`。存储在该目录中的信息属于敏感数据，因此 **请务必妥善保管**。

CLI 在向服务器发出请求时会自动查找凭据。如果访问令牌已过期，CLI 将使用刷新令牌获取新的访问令牌。

> [!NOTE]
> 如果你的组织使用单点登录，请在浏览器中选择企业登录选项并输入你的工作邮箱地址。Tuist 可以从你现有的组织成员资格或 <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">已验证的登录邮箱域</.localized_link> 中找到提供商。

## OIDC 令牌 {#oidc-tokens}

对于支持 OpenID Connect (OIDC) 的 CI 环境，Tuist 可以自动进行身份验证，无需你管理长期有效的密钥。在受支持的 CI 环境中运行时，CLI 会自动检测 OIDC 令牌提供商，并将 CI 提供的令牌交换为 Tuist 访问令牌。

### 支持的提供商 {#supported-ci-providers}

Tuist 识别以下 CI 提供商，并通过你的仓库连接将其令牌映射到项目：

- GitHub Actions
- CircleCI
- Bitrise

[Amp](#amp-orbs) orbs 通过你连接到 Tuist 账户的 Amp 工作区进行身份验证，而 [Claude Code 会话](#claude-code-sessions) 则通过你连接以在 Tuist Sandboxes 上运行的 Claude Code 环境进行身份验证。

任何其他颁发 OpenID Connect 令牌的 identity provider 都可以通过 [工作负载身份信任策略](#workload-identity-trust-policies) 进行身份验证，你只需为账户中的所有当前和未来项目配置一次即可，例如 [Fly.io Machines](#flyio-machines)。

### 设置 OIDC 身份验证 {#setting-up-oidc-authentication}

对于 GitHub Actions、CircleCI 和 Bitrise：

1. **将你的仓库连接到 Tuist**：按照 <.localized_link href="/guides/integrations/gitforge/github">GitHub 集成指南</.localized_link> 将你的 GitHub 仓库连接到你的 Tuist 项目。

2. **授予身份令牌**：在 GitHub Actions 中，为作业赋予 `permissions: id-token: write`；在 CircleCI 和 Bitrise 中，为项目启用 OIDC。从 Tuist 4.218.0 开始，当 CLI 未登录且未设置 `TUIST_TOKEN` 时，它会检测 CI 环境并在首次请求时交换身份令牌，因此无需登录步骤。早期版本需要先运行 `tuist auth login`，你仍然可以运行它以显式登录，并在交换被拒绝时尽早失败。

请参阅 <.localized_link href="/guides/integrations/continuous-integration">持续集成指南</.localized_link> 以获取特定于提供商的配置示例。

### Amp orbs {#amp-orbs}

[Amp](https://ampcode.com) orbs 可以生成标识其 Amp 工作区的 OIDC 令牌。只需将工作区连接到你的 Tuist 账户一次，该工作区中任何 orb 内的 Tuist CLI 和 `tuist_ex` Mix 任务都会自行登录，无需存储令牌或执行登录步骤：

1. 查找 ID：在运行于 orb 中的工作区线程中，运行 `echo $AMP_WORKSPACE_ID $AMP_PROJECT_ID`。
2. 在你的 Tuist 账户中，打开 **Settings → Integrations**，在 Amp 卡片上选择 **Connect workspace**，并粘贴工作区 ID。如果只允许一个 Amp 项目的 orbs 接入，还需粘贴其项目 ID。你需要是账户管理员或所有者。
3. 在工作区的 orbs 中使用 Tuist。当未登录时，CLI 或 Mix 任务会检测到 orb，使用 `amp orb id-token --audience https://tuist.dev` 生成令牌，并将其交换为 Tuist 会话。`tuist auth login` 和 `mix tuist.login` 会显式执行相同的交换操作。

与 [Amp 的 OIDC 指南](https://ampcode.com/manual/orbs/oidc) 中的信任配置类似，Tuist 会验证每个令牌上的 Amp 签名，仅当其受众为 `https://tuist.dev`、`token_use` 为 `exchanged`、`workspace_id` 与已连接的工作区匹配，并且对于限制为项目的连接，其 `project_id` 与该项目匹配时才接受。其 `sub` 必须命名与这些声明相同的工作区，对于项目连接则命名相同的项目：`workspace:<workspace-id>:project:<project-id>:…`，这是 `amp orb id-token` 默认生成的。

连接允许的每个 orb 都能获得对账户拥有的所有当前和未来项目的 CI 访问权限，包括缓存上传。它还获得 `account:sandboxes:write` 作用域，因此可以像账户成员一样创建 <.localized_link href="/guides/features/sandboxes">sandboxes</.localized_link> 并在其中运行命令，例如从 Linux orb 在 macOS sandbox 上进行构建。仅连接你信任其成员拥有该访问权限的工作区。仔细检查 ID：Tuist 无法确认你属于所连接的工作区。如果一个工作区连接到多个 Tuist 账户，orbs 必须将 `TUIST_OIDC_ACCOUNT` 设置为要登录的账户；在 Amp 项目的环境中设置它也可以将登录固定到你的账户。工作区之外的线程没有工作区身份，无法使用连接。从 Amp 卡片断开工作区以停止新登录；已颁发的会话在一小时后过期之前保持有效。会话不需要刷新令牌：当一个会话即将过期时，orb 中的 CLI 会生成一个新的 Amp 令牌并再次交换，因此只要工作区保持连接，长时间运行的 orbs 就会保持登录状态。

你在连接工作区之前为 Amp issuer 创建的信任策略在设置 `TUIST_OIDC_ACCOUNT` 时仍然有效。

### Claude Code 会话 {#claude-code-sessions}

自托管环境中的每个 Claude Code 云会话都携带一个由 Anthropic 签名的身份令牌（`CLAUDE_CODE_SESSION_ACCESS_TOKEN`）。在你 <.localized_link href="/guides/features/sandboxes/claude#claude-code">连接以在 Tuist Sandboxes 上运行</.localized_link> 的环境中，Tuist 将其作为 `TUIST_OIDC_TOKEN` 传递给会话，因此 Tuist CLI 和 `tuist_ex` Mix 任务会自行登录。

Tuist 会验证 Anthropic 的签名，仅当令牌是会话令牌（`ccr:role` 为 `session_worker`）且其受众中命名的环境已连接到 Tuist 账户并启用时，才接受该令牌。已连接环境的每个会话都能获得对账户拥有的所有当前和未来项目的 CI 访问权限，包括缓存上传，因此你的 Claude 组织允许使用该环境的任何人都可以向你的缓存发布内容。会话的 Tuist 会话在一小时后或随其身份令牌过期，以先到者为准；该令牌是会话启动时使用的令牌，默认持续四小时，因此更长的会话将失去 Tuist 访问权限，直到其下一条消息在新的 runner 上恢复它。断开或禁用环境以停止新登录。

### 工作负载身份信任策略 {#workload-identity-trust-policies}

信任策略允许来自其他身份提供商（例如部署平台、Kubernetes 集群或自管理的 CI 系统）的工作负载在没有长期有效的 Tuist 密钥的情况下访问项目。提供商必须：

- 在公共地址上可通过 HTTPS 访问。Tuist 不遵循重定向，也不连接到私有或内部网络地址，包括来自自托管 Tuist 服务器的连接。
- 颁发使用非对称密钥签名的 JWT，例如 `RS256` 或 `ES256`。未签名的令牌和使用共享密钥签名的令牌（`HS256` 及类似算法）将被拒绝。
- 在固定的 HTTPS URL 上将其签名密钥发布为 JSON Web Key Set (JWKS)。响应最多为 64 KiB，且最多包含 20 个密钥。
- 在每个令牌中包含过期时间 (`exp`)。

GitHub Actions、CircleCI 和 Bitrise 发行方保留用于上述基于存储库的流程，不能用于信任策略。

> [!NOTE]
> 对于自托管部署，在配置工作负载身份或将作业迁移到它们之前，应用数据库迁移并升级每个正在服务的 Tuist 服务器副本。然后将 CLI 或 Elixir 集成升级到支持 `TUIST_OIDC_TOKEN` 和 `TUIST_OIDC_ACCOUNT` 的版本。现有的 GitHub Actions、CircleCI 和 Bitrise 作业继续使用基于存储库的授权，不需要账户句柄。在切换生产作业之前，验证与预期工作负载的短期令牌交换和缓存操作。要停止新的交换，请删除策略；允许已颁发的 Tuist 访问令牌在一小时内过期。删除策略不会立即撤销这些令牌。

#### 创建策略 {#create-a-trust-policy}

在 Tuist 仪表板中，打开你账户的 **Settings** > **Authentication**，找到 **Workload identities** 部分。你必须是账户管理员（或个人账户的所有者）。每个账户最多可以有 20 个策略。配置一次身份以获得账户范围的 CI 访问权限；无需选择项目。

使用 **Workload identities** 旁边的开关打开策略表单。当账户有已保存的身份时，开关初始为开启状态，并在保存后保持开启。对于没有身份的账户，开关初始为关闭。该部分出现在组织的 **SCIM provisioning** 下方。隐藏表单会保留你的草稿，并且不会禁用工作负载身份验证：已保存身份的卡片和设置文档链接仍然可见。每张卡片显示身份的名称、发行方和 JWKS URL、受众、精确的 JSON 声明、账户范围的作用域和创建时间。使用卡片上的操作移除身份。

选择 **Custom provider** 以输入以下字段，或选择 **Fly.io Machines** 以根据你的组织 slug 以及数字组织和应用程序 ID 生成它们。Fly 模板使生成的发行方、JWKS URL 和声明在 **Advanced configuration** 下可编辑。更改模板或辅助值会保留你手动编辑的字段。如果你的发行方、JWKS URL 或声明覆盖了模板，Tuist 会展开 **Advanced configuration** 并显示警告，以便你可以审查将要保存的策略。切换回 **Custom provider** 以在没有 Fly 辅助的情况下继续。模板仅填充配置，不会改变 Tuist 验证令牌的方式。

| 字段 | 描述 |
| --- | --- |
| 名称 | 用于识别策略的标签，在账户内唯一。 |
| 发行方 URL | 令牌的 `iss` 声明。它必须完全匹配，包括任何尾部斜杠。 |
| JWKS URL | 提供商签名密钥的 HTTPS URL。Tuist 直接使用此 URL，不读取提供商的 OpenID Connect 发现文档，因此请从提供商的文档或 `<issuer>/.well-known/openid-configuration` 复制 `jwks_uri`。 |
| 受众 | 令牌必须为其颁发的受众，默认为 `tuist`。令牌的 `aud` 必须等于它，或者当 `aud` 是列表时包含它。使用只有 Tuist 接受的值，以便为其他服务生成的令牌不能在此处重放。 |
| 声明 | 一个包含 1 到 10 个令牌必须包含的声明的 JSON 对象，例如 `{"sub": "system:serviceaccount:ci:builder"}`。JSON 输入限制为 8 KiB。值必须是字符串、有符号 64 位整数或布尔值，并且必须完全匹配，包括其类型：`"123"` 与 `123` 不匹配。不允许嵌套对象、列表以及时间或令牌声明，如 `iss`、`aud`、`exp`、`nbf`、`iat` 和 `jti`。 |

每个策略授予对 **账户拥有的所有当前和未来项目** 的 CI 访问权限，无需选择单个项目。你可以在创建第一个项目之前配置身份。这不授予账户管理权限或对其他账户的访问权限。

每个能够获得具有匹配声明的令牌的工作负载都可以访问所有这些项目，因此请选择提供商保证且无人可以重用的声明。优先使用稳定的数字 ID，而不是可以在删除后重命名或重新注册的名称。

> [!WARNING]
> 在共享身份提供商上，将策略绑定到你的组织或租户 **以及** 目标应用程序、项目或服务账户。仅使用分支名称（如 `main`）、环境（如 `production`）或通用角色不足以构成身份边界：其他租户可能获得具有相同值的令牌。例如，GitLab.com 策略必须包含目标项目的稳定 `project_id`，而不仅仅是 `ref`。匹配的令牌授予账户范围内的 CI 访问权限，包括缓存写入，因此信任无关工作负载的策略可能导致缓存投毒。

Tuist 仅在检查发行方、受众、过期时间、生效前时间（允许最多 60 秒的时钟偏差）以及每个声明后，为那些其 JWKS URL 持有签名密钥的策略授予访问权限。颁发的一小时 CI 令牌适用于整个账户，而非项目 ID 的快照：它包括颁发后创建或转移到该账户的项目。项目授权仍然需要当前的账户所有权，因此将项目转出会移除其在该账户令牌下的访问权限。

#### 验证工作负载 {#authenticate-a-workload}

1. 从你的提供商请求一个具有策略受众的身份令牌。
2. 将 `TUIST_OIDC_TOKEN` 设置为该令牌，并将 `TUIST_OIDC_ACCOUNT` 设置为拥有该项目的 Tuist 账户句柄。每次信任策略交换都需要提供账户。它仅选择查找位置，本身不授予任何权限。
3. 运行 Tuist。当没有 `TUIST_TOKEN` 或有效的存储凭据时，CLI 和 Elixir 集成会自动交换令牌。`tuist auth login` 和 `mix tuist.login` 显式执行相同的交换。

生成的 Tuist 访问令牌仅具有 `ci` 范围组，并涵盖所选账户拥有的所有当前和未来项目。如果账户中有超过 20 个策略匹配同一令牌，或者它们使用超过两个不同的 JWKS URL，则交换会失败。

Tuist 不会刷新这些会话。访问令牌在一小时后过期，且没有刷新令牌。提供商身份令牌通常仅在几分钟内有效，因此保留旧的 `TUIST_OIDC_TOKEN` 不是续期策略：对于运行时间超过一小时的任务，请在 Tuist 会话过期之前请求新的身份令牌并重新登录。移除策略会停止新的交换，但已颁发的访问令牌在过期前仍然有效。

Tuist 在专用且大小受限的缓存中缓存提供商的签名密钥，成功获取后最多保留 15 分钟。条目可能会更早被驱逐并再次获取。失败的获取不会被缓存。如果你的提供商轮换密钥，它应在使用新密钥签名令牌之前至少 15 分钟将其发布到 JWKS 中，因为使用不在缓存集中的密钥签名的令牌会被拒绝，直到缓存过期。只有当 JWKS 包含单个符合条件的签名密钥时，才接受没有密钥 ID (`kid`) 的令牌。当 JWKS 中存在密钥 ID 时，它必须是长度不超过 256 字节的字符串。

> [!NOTE]
> `TUIST_OIDC_TOKEN` 是通用令牌输入，不是绕过服务器信任的方法。它优先于 CI 提供商检测，服务器仍然只接受内置提供商和具有匹配信任策略的身份。不要将身份令牌放入 `TUIST_TOKEN`，因为它期望的是 Tuist 凭据。

如果交换失败，请检查策略中的发行方、受众和每个声明是否与令牌完全匹配，JWKS URL 是否提供签名令牌的密钥，策略是否未被移除，以及 `TUIST_OIDC_ACCOUNT` 是否命名了拥有该项目的账户。为了避免暴露哪些身份受信任，Tuist 对所有这些情况返回相同的错误。

### Fly.io Machines {#flyio-machines}

[Fly.io 支持 OIDC 工作负载身份](https://docs.fly.io/reference/openid-connect/)。Machine 可以从其本地 `/.fly/api` Unix 套接字请求短期的签名身份令牌，无需 Fly API 令牌或长期的 Tuist 秘密。Fly 令牌标识组织和应用程序，而非源代码仓库，因此请使用信任策略而不是连接 GitHub 仓库：

1. 从在你的 Fly Machine 内部颁发的身份令牌中获取发行方 (`iss`)、组织 ID (`org_id`) 和应用程序 ID (`app_id`)。发行方为 `https://oidc.fly.io/<organization-slug>`。使用数字 ID，而不是组织或应用程序名称。
2. 使用 **Fly.io Machines** 模板 [创建信任策略](#create-a-trust-policy)，并输入组织 slug 和两个数字 ID。它会填充下面的值并将 ID 保持为字符串。你也可以使用 **自定义提供商** 手动输入它们；在声明中保留 ID 周围的引号。

   | 字段 | 值 |
   | --- | --- |
   | 发行方 URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | 受众 | `tuist` |
   | 声明 | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. 在 Machine 内部，将 `TUIST_OIDC_ACCOUNT` 设置为拥有该项目的 Tuist 账户句柄（而非 Fly 组织 slug），请求受众为 `tuist` 的令牌，并使用 `TUIST_OIDC_TOKEN` 将其传递给 `tuist auth login`：

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

对于初始设置，你可以在导出令牌后、取消设置之前，仅在本地检查身份字段。这会解码声明以进行配置；Tuist 在身份验证期间单独验证签名：

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

不要打印或提交令牌本身。授权 Fly 应用中的每个 Machine 都可以对 Tuist 账户中的所有当前和未来项目进行身份验证。为每个额外的应用程序创建单独的策略。Fly 身份令牌大约在十分钟后过期，因此在长时间运行的 Machine 上，请在 Tuist 会话过期之前请求新的令牌并再次运行 `tuist auth login`。

### OIDC 令牌范围 {#oidc-token-scopes}

OIDC 令牌被授予 `ci` 范围组。对于 GitHub Actions、CircleCI 和 Bitrise，这提供对连接到仓库的所有项目的访问权限。对于连接的 Amp 工作区、连接的 Claude Code 环境和工作负载身份信任策略，这提供对所选账户拥有的所有当前和未来项目的访问权限，而不授予项目创建、项目管理、Runner 管理或账户成员管理权限。有关 `ci` 范围包含内容的详细信息，请参阅 [范围组](#scope-groups)。

> [!TIP]
> **安全优势**
>
> OIDC 身份验证比长期令牌更安全，因为：
> - 无需轮换或管理秘密
> - 令牌生命周期短
> - 身份验证与你的仓库身份或明确授权的工作负载身份绑定


## Gradle 插件身份验证 {#gradle-plugin-authentication}

Gradle 插件使用 Tuist CLI 的身份验证状态，不定义单独的登录流程。只需通过 CLI 进行一次身份验证，插件就会重用这些凭据。

对于项目和服务器配置（包括 `project` 和 `url`），请使用规范的 <.localized_link href="/references/tuist-toml">tuist.toml 参考</.localized_link>。

对于本地使用，请运行：

```bash
tuist auth login
```

对于 CI，可以使用以下任一方式：

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC 身份验证</.localized_link>（如果可用，推荐使用）
- 通过 `TUIST_TOKEN` 进行 <.localized_link href="/guides/server/authentication#continuous-integration">账户令牌身份验证</.localized_link>

对于自托管的 Tuist 服务器，请在 `tuist.toml` 中定义服务器 URL（例如 `url = "https://tuist.your-company.com"`）并运行标准登录流程。该 URL 从插件使用的同一配置文件中解析。

配置好身份验证后，正常运行你的 Gradle 缓存命令和任务。

## 账户令牌 {#account-tokens}

对于不支持 OIDC 的 CI 环境，或者当你需要对权限进行细粒度控制时，可以使用账户令牌。账户令牌允许你精确指定令牌可以访问的范围和项目。

### 创建账户令牌 {#creating-an-account-token}

创建账户令牌最简单的方法是从仪表板操作：

1. 在 Tuist 仪表板中打开组织。
2. 转到 **设置** > **令牌**。
3. 选择 **生成令牌**。
4. 选择名称、可选的过期时间、项目访问权限以及令牌所需的范围。
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
| `--scopes` | 必填。要授予令牌的范围列表，以空格分隔。 |
| `--name` | 必填。令牌的唯一标识符（1-32 个字符，仅限字母数字、连字符和下划线）。 |
| `--expires` | 可选。令牌的过期时间。使用类似 `30d`（天）、`6m`（月）或 `1y`（年）的格式。如果未指定，令牌永不过期。 |
| `--projects` | 将令牌限制为特定的项目句柄。如果未指定，令牌可以访问所有项目。 |

### 可用范围 {#available-scopes}

| 范围 | 描述 |
| --- | --- |
| `account:cache:read` | 下载账户范围的缓存二进制文件 |
| `account:cache:write` | 上传账户范围的缓存二进制文件 |
| `account:members:read` | 读取账户成员 |
| `account:members:write` | 管理账户成员 |
| `account:registry:read` | 从 Swift 包注册表读取 |
| `account:registry:write` | 发布到 Swift 包注册表 |
| `account:runners:read` | 读取 Runner 作业、工作流、配置文件和卷 |
| `account:runners:write` | 管理 Runner 配置文件并删除 Runner 卷 |
| `account:sandboxes:write` | 创建沙盒并在其中运行命令，就像账户成员一样 |
| `project:previews:read` | 下载预览 |
| `project:previews:write` | 上传预览 |
| `project:admin:read` | 读取项目及其设置 |
| `project:admin:write` | 创建、更新和删除项目。创建项目需要拥有所有项目访问权限的令牌 |
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

### 范围组 {#scope-groups}

范围组提供了一种便捷的方式，可以通过单个标识符授予多个相关范围。当你使用范围组时，它会自动展开以包含其包含的所有单独范围。

| 范围组 | 包含的范围 |
| --- | --- |
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### 持续集成 {#continuous-integration}

对于不支持 OIDC 的 CI 环境，请使用带有 `ci` 范围组的账户令牌来验证你的 CI 工作流。在仪表板中生成令牌时，选择 **CI** 预设。

你也可以从 CLI 创建相同的令牌：

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

这将创建一个包含典型 CI 操作所需所有范围的令牌（缓存、预览、捆绑包、测试、构建和运行）。将生成的令牌作为机密存储在 CI 环境中，并将其设置为 `TUIST_TOKEN` 环境变量。

### 管理账户令牌 {#managing-account-tokens}

在账户仪表板中打开 **设置** > **令牌**，以查看账户令牌、检查令牌的范围和项目访问权限，并在轮换期间撤销令牌。

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
> - 令牌可以访问账户内的多个项目
> - 具有自动过期功能的时间限制令牌
