---
{
  "title": "单点登录",
  "titleTemplate": ":title | 身份验证 | 集成 | 指南 | Tuist",
  "description": "了解如何配置单点登录、验证登录邮箱域名，以及选择用户加入组织的方式。"
}
---
# 单点登录 {#single-sign-on}

Tuist 提供单点登录作为登录选项，为你的组织账户提供额外的安全保障。

单点登录在组织设置中的 **身份验证** 标签页进行配置。支持 Google Workspace、Okta、Microsoft Entra ID 以及自定义 [OAuth 2.0](https://oauth.net/2/) 提供商。

Microsoft Entra ID 是一个 OpenID Connect 提供商，Tuist 会根据你的目录标识符为你进行配置。本指南中针对自定义提供商描述的所有内容（包括登录邮箱域名验证和注册）同样适用于它。

> [!NOTE]
> 单点登录控制成员的身份验证方式以及已认证用户是否可以自动加入。<.localized_link href="/guides/integrations/authentication/scim">跨域身份管理系统配置</.localized_link> 控制身份提供商是否可以创建、更新和取消配置组织成员。对于 Okta，大多数组织会同时配置这两项。

## 访问机制 {#how-access-works}

提供商身份、登录发现和组织注册是相互独立的概念：

- **提供商颁发者：** 对用户进行身份验证的提供商组织或授权服务器。Tuist 在查找关联身份时会结合提供商、颁发者和稳定的提供商用户标识符。对于 Okta，颁发者由 Okta 域名表示。对于 Microsoft Entra ID，它派生自目录（租户）标识符。对于自定义提供商，它由提供商 URL 表示。
- **登录邮箱域名：** Tuist 用于从通用登录页面发现 Okta 或自定义提供商的邮箱域名。验证通过后，它还会确定哪些邮箱地址可用于新账户关联和自动注册。
- **注册策略：** 决定来自可信域的用户是需要邀请还是可以自动加入。
- **配置：** 独立于登录流程创建和管理组织成员资格。

提供商颁发者和登录邮箱域名通常不同。例如，公司可能使用 `example.com` 作为员工邮箱，而其提供商颁发者是 `https://login.vendor.example.net`。新的 Okta 和自定义提供商配置会分别存储这些值。

### 验证登录邮箱域名 {#verify-a-login-email-domain}

Okta 和自定义提供商配置要求先验证登录邮箱域名，然后才能创建新的 Tuist 账户或通过邮箱地址关联现有账户。在域名未验证期间，成员仍然可以 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">关联其现有账户</.localized_link>。

1. 在 **登录邮箱域名** 中输入员工邮箱域名，例如 `example.com`。
2. 保存单点登录配置。
3. 将 Tuist 显示的文本记录添加到域名的 [域名系统](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) 配置中。
4. 返回身份验证设置并点击 **验证域名**。

一个已验证的登录邮箱域名只能属于一个 Tuist 组织。更改域名会清除其验证状态，并要求发布新的文本记录。在域名验证通过之前，自动注册将保持暂停状态。

Tuist 每天重新检查文本记录。如果记录停止解析，验证状态不会立即清除：域名保留该状态 14 天，且身份验证设置会显示 **验证即将过期** 以及需要再次发布的记录。发布记录并验证后可清除警告。如果 14 天后记录仍然缺失，域名将恢复为未验证状态，提供商发现、身份关联和自动注册将停止，直到再次验证为止。因其他原因导致的查找失败不会刷新计时器，也不会自行清除验证状态。在引入每日重新检查之前已验证的域名不会重新检查。

Google Workspace 不需要这个单独的 Tuist 验证步骤，因为 Google 会将已验证的 Workspace 域名作为已认证身份的一部分提供。

### 选择注册策略 {#choose-an-enrollment-policy}

Tuist 支持两种注册策略：

- **仅限邀请：** 用户需要组织邀请。对于 Okta 和自定义提供商，在提供商创建全新的 Tuist 账户之前，必须验证登录邮箱域名。拥有现有 Tuist 账户的被邀请用户需先接受邀请，然后按照 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">关联现有 Tuist 账户</.localized_link> 中的说明关联提供商身份。
- **自动：** 经过身份验证的邮箱与可信域匹配的用户可以在无需邀请的情况下创建或关联账户并加入组织。Google 配置使用 Workspace 域名。Okta 和自定义提供商要求验证登录邮箱域名。

Google 配置默认为自动注册。新的 Okta 和自定义提供商配置默认为仅限邀请注册。

**强制单点登录** 设置与注册无关。强制启用可防止现有组织成员使用邮箱和密码登录；它并不授予组织成员资格。

### 选择注册成员获得的角色 {#choose-the-enrollment-role}

自动加入的成员将获得在 **注册成员角色** 下设置的 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>，除非管理员更改，否则默认为 `user`。将其设置为 `viewer` 可以让目录中的所有人登录，但不会赋予所有人修改内容的权限。

该设置不能设置为 `admin`，适用于通过 <.localized_link href="/guides/integrations/authentication/scim">SCIM</.localized_link> 配置且没有角色的成员，也适用于登录的成员，并且永远不会覆盖管理员手动设置的角色。

### 关联现有 Tuist 账户 {#link-an-existing-account}

关联的提供商身份会登录到整个 Tuist 账户，包括该账户所属的所有其他组织。对于 Okta 和自定义提供商，只有当现有账户的邮箱地址位于已验证的登录邮箱域名上，或者组织的 SCIM 配置创建了该账户时，Tuist 才会自动关联现有账户。

不符合条件的账户成员需自行关联身份：

1. 使用账户常用的登录方法登录 Tuist。
2. 从身份提供商处打开 Tuist（例如其应用磁贴），或者如果组织强制单点登录，则打开该组织的一个项目。
3. 确认 Tuist 显示的组织及身份提供商账户，然后点击 **关联账户**。

未登录时通过单点登录发起的成员会被要求先登录，之后 Tuist 会返回到确认页面。关联不依赖于域名验证，因此成员可以在域名验证之前使用单点登录。

### 现有组织 {#existing-organizations}

所有 Okta 和自定义提供商组织均使用已验证域名模型。临时兼容模式已被移除。

如果您的登录邮箱域名未经验证：

- 现有已关联成员可以继续登录，且现有的 SSO 强制策略仍适用于组织成员。
- 登录页面仅通过现有组织成员关系来发现您的提供商。
- 自动注册已暂停，提供商无法创建新的 Tuist 账户，即使有邀请也不行。
- 未关联成员需登录其现有的 Tuist 账户并按上述说明确认关联。由组织的 SCIM 配置创建的账户仍可在首次 SSO 登录时进行关联。
- 新注册用户并不因其邮箱地址使用您的域名而被强制要求使用您的提供商。

现有已启用的注册和强制设置仍保持保存状态，可以关闭。管理员可以在域名未验证时编辑配置；启用任一设置都需要验证。当启用该设置时，验证会为匹配的邮箱地址恢复自动注册。Google Workspace 的行为保持不变。

您的 **登录邮箱域名** 可能已根据组织成员信息自动填充。确认该值，发布文本记录，然后点击 **验证域名**。保持记录发布状态以便每日重新检查。

## Google Workspace {#google}

Google Workspace 单点登录针对 Workspace 域对用户进行身份验证。管理员可以允许匹配的用户自动加入或要求邀请。

> [!NOTE]
> **前提条件**
>
> 您需要一个拥有已验证域名的 Google Workspace 组织。您还必须使用与您要设置的域名绑定的邮箱通过 Google 进行身份验证。

### 设置 {#google-setup}

1. 导航到您组织的 **身份验证** 设置标签页。
2. 启用单点登录。
3. 选择 **Google** 作为提供商。
4. 输入您的 Google Workspace 域名，例如 `example.com`。
5. 选择 **自动注册** 或仅限邀请注册。Google 默认启用自动注册。
6. 测试登录流程后，可选择启用 **强制单点登录**。
7. 点击 **保存更改**。

## Okta {#okta}

Okta 使用 [OpenID Connect](https://openid.net/developers/how-connect-works/) 对成员进行身份验证。Okta 域名标识提供商颁发者；单独验证的登录邮箱域名控制发现、新账户关联和注册。

如果您还希望 Okta 自动创建、更新或取消配置成员，请在单点登录正常工作后配置 <.localized_link href="/guides/integrations/authentication/scim#okta">Okta 跨域身份管理系统配置</.localized_link>。

### 步骤 1：创建 Okta 应用 {#okta-step-1}

1. 在 Okta 管理仪表板中，转到 **Applications > Applications > Create App Integration**。
2. 选择 **OpenID Connect** 和 **Web Application**。
3. 设置应用名称，例如 `Tuist`。可选上传 [Tuist 徽标](https://tuist.dev/images/tuist_dashboard.png)。
4. 将 **Sign-in redirect URI** 设置为身份验证设置页面上显示的值，例如 `https://tuist.dev/users/auth/okta/callback`。
5. 在 **Assignments** 下，选择所需的访问控制并保存。
6. 从应用的常规设置中复制 **Client ID** 和 **Client Secret**。记下您的 **Okta 域名**，例如 `your-company.okta.com`。
7. 可选地，为了允许从 Okta 仪表板登录，请在常规设置上点击 **Edit**，将 **Login initiated by** 更改为 **Either Okta or App**，选择 **Display application icon to users**，并将 **Initiate login URI** 设置为身份验证设置页面上显示的值。

### 步骤 2：配置 Tuist {#okta-step-2}

1. 导航到您组织的 **身份验证** 设置标签页。
2. 启用单点登录。
3. 选择 **Okta** 作为提供商。
4. 输入 **Okta 域名**、**Client ID** 和 **Client Secret**。
5. 在 **登录邮箱域名** 下输入员工邮箱域名。例如，Okta 域名为 `your-company.okta.com` 时，其登录邮箱域名可能为 `example.com`。
6. 点击 **保存更改**。
7. 将 Tuist 显示的文本记录添加到登录邮箱域名，然后点击 **验证域名**。
8. 选择用户需要邀请还是可以自动注册，然后再次保存配置。
9. 测试登录流程后，可选择启用 **强制单点登录**。

### 步骤 3：为用户分配 Okta 应用权限 {#okta-step-3}

分配应允许通过 Okta 应用进行身份验证的用户或组。

分配授予访问登录流程的权限，但组织成员资格仍遵循注册策略。如果同一用户通过跨域身份管理系统进行配置，Tuist 会在用户首次登录时将 Okta 身份与 SCIM 创建的账户关联。对于在 SCIM 添加之前已存在账户的成员，当其邮箱地址位于已验证的登录邮箱域名中，或从其已登录的账户确认关联后，将进行关联。

## Microsoft Entra ID {#microsoft-entra-id}

Microsoft Entra ID 通过 [OpenID Connect](https://openid.net/developers/how-connect-works/) 对成员进行身份验证。Tuist 从您的目录（租户）标识符派生授权、令牌和用户信息端点，因此您只需输入该值以及应用凭据。

如果您还希望 Entra ID 自动创建、更新或取消配置成员，请在单点登录正常工作后配置 <.localized_link href="/guides/integrations/authentication/scim#microsoft-entra-id">Microsoft Entra ID 跨域身份管理系统配置</.localized_link>。

### 步骤 1：注册 Entra 应用 {#entra-step-1}

1. 在 [Microsoft Entra 管理中心](https://entra.microsoft.com) 中，转到 **Identity > Applications > App registrations > New registration**。
2. 设置应用名称，例如 `Tuist`。
3. 在 **Redirect URI** 下，选择 **Web** 平台并输入身份验证设置页面上显示的值，例如 `https://tuist.dev/users/auth/oauth2/callback`。
4. 注册应用，然后从其概览页面复制 **Directory (tenant) ID** 和 **Application (client) ID**。
5. 转到 **Certificates & secrets > New client secret**，创建密钥并复制其 **Value**。Microsoft 仅显示一次该值，且每个客户端密钥都有过期日期，因此请记录需要轮换的时间。
6. 转到 **API permissions** 并确认已授予委托的 Microsoft Graph 权限 `openid`、`profile` 和 `email`。
7. 可选地，为了让成员从 My Apps 门户启动登录流程，请将 **Branding & properties** 下的 **Home page URL** 设置为身份验证设置页面上显示的值。

### 步骤 2：配置 Tuist {#entra-step-2}

1. 导航到您组织的 **身份验证** 设置标签页。
2. 启用单点登录。
3. 选择 **Microsoft Entra ID** 作为提供商。
4. 输入 **Directory (tenant) ID**、**Client ID** 和 **Client Secret**。
5. 在 **登录邮箱域名** 下输入员工邮箱域名。例如，用户以 `first.last@example.com` 形式登录的目录，其登录邮箱域名为 `example.com`。
6. 点击 **保存更改**。
7. 将 Tuist 显示的文本记录添加到登录邮箱域名，然后点击 **验证域名**。
8. 选择用户需要邀请还是可以自动注册，然后再次保存配置。
9. 测试登录流程后，可选择启用 **强制单点登录**。

### 步骤 3：为用户分配 Entra 应用权限 {#entra-step-3}

分配应允许进行身份验证的用户或组。如果应用配置为需要分配，则只有被分配的用户才能登录。

分配授予访问登录流程的权限，但组织成员资格仍遵循注册策略。如果同一用户通过跨域身份管理系统进行配置，Tuist 会在用户首次登录时将 Entra 身份与 SCIM 创建的账户关联。对于在 SCIM 添加之前已存在账户的成员，当其邮箱地址位于已验证的登录邮箱域名中，或从其已登录的账户确认关联后，将进行关联。

### 邮箱声明的要求 {#entra-email-claim}

Tuist 从 Microsoft Graph 用户信息端点读取经过身份验证的用户个人资料，该端点仅在用户有可用邮箱地址时返回。如果目录用户的 `mail` 属性为空，则无法登录，因为 Tuist 没有可与登录邮箱域名匹配的地址。

在推出单点登录之前，请确认您分配的成员在目录中已填充邮箱地址。从本地 Active Directory 同步但没有邮箱的用户是缺少此属性的最常见情况。

### 条件访问和多因素身份验证 {#entra-conditional-access}

条件访问策略、多因素身份验证和登录风险策略以与适用于任何其他 Entra 应用相同的方式适用于 Tuist 应用，因为它们在授权请求期间进行评估。无需额外的 Tuist 配置。

## 自定义 OAuth 2.0 提供商 {#custom-oauth-2-provider}

自定义 OAuth 2.0 提供商允许组织使用 Google Workspace 或 Okta 以外的身份服务。提供商的用户信息端点必须返回稳定的用户标识符和邮箱地址。

1. 在提供商处，创建一个 OAuth 2.0 Web 应用。
2. 将 **登录重定向 URI** 和可选的 **发起登录 URI** 设置为 Tuist 身份验证设置中显示的值。
3. 在 Tuist 中，启用单点登录并选择 **OAuth2**。
4. 输入提供商 URL、授权端点、令牌端点、用户信息端点、客户端标识符和客户端密钥。
5. 输入并保存 **登录邮箱域名**。这是员工邮箱域名，而非提供商 URL。
6. 将 Tuist 显示的文本记录添加到登录邮箱域名，然后点击 **验证域名**。
7. 选择仅限邀请或自动注册，并保存配置。
8. 在可选择启用 **强制单点登录** 之前，先测试登录。

提供商 URL 将身份范围限定为颁发提供商。已验证的登录邮箱域名决定了 Tuist 在关联或注册用户时可以信任哪些邮箱地址。

## 命令行配置 {#command-line-configuration}

命令行界面可以配置 Google Workspace 或 Okta 并选择注册策略。例如：

```bash
tuist organization update sso example \
  --provider okta \
  --organization-id your-company.okta.com \
  --enrollment-policy invitation-only
```

Microsoft Entra ID 和自定义提供商是通过组织的身份验证设置而非命令行进行配置的。

`--organization-id` 值用于标识提供商组织。它不是登录邮箱域名。在注册新的 Okta 用户之前，请从组织的身份验证设置中添加并验证登录邮箱域名。

## 故障排除 {#troubleshooting}

### 现有成员可以登录，但新用户无法登录 {#existing-members-can-sign-in-but-new-users-cannot}

对于 Okta 和自定义提供商配置，请确认登录邮箱域名已验证。然后邀请用户或启用自动注册。

### 单点登录要求你先登录 {#single-sign-on-asks-you-to-log-in-first}

你的 Tuist 账户邮箱地址不在组织已验证的登录邮箱域名中，或者该域名尚未验证，因此 Tuist 不会自动关联提供商身份。使用你常用的登录方式登录并确认关联，如 <.localized_link href="/guides/integrations/authentication/sso#link-an-existing-account">关联现有 Tuist 账户</.localized_link> 中所述。
### Tuist 无法找到与邮箱地址对应的组织 {#tuist-cannot-find-an-organization-for-an-email-address}

确认用户输入了预期的员工邮箱地址，且其域名与已验证的登录邮箱域名完全匹配。也可以通过现有成员的组织成员资格来发现他们。

### 域名验证仍处于待处理状态 {#domain-verification-remains-pending}

确认文本记录的名称和值与 Tuist 中显示的值完全匹配。域名系统更改可能需要时间传播，因此在记录公开可用后重试验证。

### 更改提供商后登录停止 {#sign-in-stopped-after-changing-the-provider}

确认新提供商配置，验证登录邮箱域名，并在启用强制执行之前测试登录流程。
