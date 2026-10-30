---
{
  "title": "SCIM 预配",
  "titleTemplate": ":title | 身份验证 | 集成 | 指南 | Tuist",
  "description": "了解如何使用 Okta 或 Microsoft Entra ID 配置 SCIM 预配。"
}
---
# SCIM 预配 {#scim-provisioning}

Tuist 支持 SCIM 2.0 预配，以便身份提供商可以自动创建、更新和取消预配组织成员。

在组织设置的 **Authentication** 选项卡中配置 SCIM。SCIM 令牌是专用于 SCIM 访问的组织级账户令牌，仅在生成时显示一次。

> [!NOTE]
> SCIM 控制成员资格和生命周期。它不会替代 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>。如果希望已预配的用户也通过你的身份提供商登录，请单独配置 SSO。

已预配的用户已经是组织成员。当他们使用相同的电子邮件地址登录时，该成员资格可以建立信任以链接其提供商身份。<.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">verified login email domain</.localized_link> 和 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">enrollment policy</.localized_link> 控制尚未预配或添加到组织的用户。

## Okta {#okta}

Okta 为 Tuist 使用两个独立的应用程序：

- 一个用于登录 Tuist 的 **OIDC Web Application**。
- 一个用于将用户和组预配到 Tuist 的 **SCIM 2.0 Test App (Header Auth)** 应用程序。

如果用户应使用 Okta 登录，请先配置 <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link>，然后按照以下步骤配置 SCIM 预配。

### 步骤 1：生成 Tuist SCIM 令牌 {#okta-step-1}

1. 在 Tuist 中，导航到你组织的 **Authentication** 设置选项卡。
2. 在 **SCIM provisioning** 部分，复制 **SCIM endpoint URL**。它应以 `/scim/v2` 结尾。
3. 点击 **Generate token**。
4. 为令牌命名（例如，`Okta`）。
5. 复制生成的令牌。Tuist 仅显示一次令牌。

### 步骤 2：添加 Okta SCIM 应用 {#okta-step-2}

1. 在你的 Okta 管理仪表板中，转到 **Applications > Applications > Browse App Catalog**。
2. 搜索并添加 **SCIM 2.0 Test App (Header Auth)**。
3. 为其指定一个易于识别的名称，例如 `Tuist SCIM`。
4. 完成 SCIM 测试应用的登录设置。Tuist 不使用此应用进行登录；登录由 SSO 指南中的 OIDC 应用程序处理。

### 步骤 3：配置 API 集成 {#okta-step-3}

1. 打开 SCIM 应用的 **Provisioning** 选项卡。
2. 在 **Settings > Integration** 下，点击 **Configure API Integration** 或 **Edit**。
3. 勾选 **Enable API integration**。
4. 将 Tuist 的 **SCIM endpoint URL** 粘贴到 Okta 的 **Base URL** 字段中。
5. 将 Tuist SCIM 令牌粘贴到 **API Token**，并在前面加上 `Bearer `。例如，`Bearer tuist_scim_...`。Okta 将此字段作为 `Authorization` 标头发送，而 Tuist 期望的是 bearer 令牌。
6. 如果你希望 Okta 读取 Tuist 的 SCIM 组，请启用 **Import Groups**。
7. 点击 **Test API Credentials**。Okta 应报告集成已成功验证。
8. 点击 **Save**。

### 步骤 4：启用预配操作 {#okta-step-4}

1. 在 SCIM 应用的 **Provisioning** 选项卡中，打开 **Settings > To App**。
2. 点击 **Edit**。
3. 启用：
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. 点击 **Save**。

### 步骤 5：分配用户或组 {#okta-step-5}

1. 打开 SCIM 应用的 **Assignments** 选项卡。
2. 分配应预配到 Tuist 的用户或组。
3. 如果这些用户或组也应能够通过 SSO 登录，请将它们分配到 Okta OIDC 应用程序。
4. 检查 Tuist 的 **Members** 选项卡，验证已分配的用户是否出现在组织中。

要测试取消预配，请在 Okta 中取消分配或停用某个用户，并验证他们从 Tuist 组织的 **Members** 选项卡中消失。

### 分配角色 {#okta-assigning-roles}

Tuist 有三个<.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。Tuist 为每个角色公开一个 SCIM 组：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。使用 **Group Push** 将 Okta 组映射到它们：

1. 为你想要分配的每个角色选择或创建一个 Okta 组，并在 SCIM 应用的 **Assignments** 选项卡上分配这些组。
2. 确保 API 集成中已启用 **Import Groups**，然后打开 SCIM 应用的 **Import** 选项卡并点击 **Import Now**，以便 Okta 了解 Tuist 的组。
3. 打开 SCIM 应用的 **Push Groups** 选项卡，然后点击 **Push Groups > Find groups by name**。
4. 选择一个 Okta 组，选择 **Link Group** 作为推送操作，并选择匹配的 Tuist 组。Tuist 不支持通过 SCIM 创建组，因此请链接到现有组，而不是创建新组。
5. 点击 **Save** 并对剩余角色重复此操作。

将用户添加到链接的组会赋予他们该角色。将他们从组中移除会将他们移回组织为单点登录成员注册的默认角色，即 `user`，除非管理员在 **Settings > Authentication** 下更改了它。不在任何链接组中的用户也会获得该角色。从组中移除用户并不会将他们从组织中移除；要在 Okta 中执行此操作，请取消分配或停用他们。

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID 通过非库企业应用程序预配 Tuist。如果用户也应使用 Entra ID 登录，请先配置 <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link>。

你为单点登录注册的应用程序和你用于预配的企业应用程序可以是同一个。预配是在企业应用程序条目上配置的。

### 步骤 1：生成 Tuist SCIM 令牌 {#entra-step-1}

1. 在 Tuist 中，导航到你组织的 **Authentication** 设置选项卡。
2. 在 **SCIM provisioning** 部分，复制 **SCIM endpoint URL**。它应以 `/scim/v2` 结尾。
3. 点击 **Generate token**。
4. 为令牌命名（例如，`Entra ID`）。
5. 复制生成的令牌。Tuist 仅显示一次令牌。

### 步骤 2：配置预配 {#entra-step-2}

1. 在 Microsoft Entra 管理中心中，转到 **Identity > Applications > Enterprise applications** 并打开 Tuist 应用程序。
2. 打开 **Provisioning** 并将 **Provisioning Mode** 设置为 **Automatic**。
3. 将 **Tenant URL** 设置为 Tuist SCIM 端点 URL。
4. 将 **Secret Token** 设置为 Tuist SCIM 令牌。单独输入令牌，不要添加 `Bearer ` 前缀；Entra ID 会自动添加方案。
5. 点击 **Test Connection**。Entra ID 应报告提供的凭据已获授权。
6. 保存配置。

### 步骤 3：设置匹配属性 {#entra-step-3}

1. 在 **Mappings** 下，打开 **Provision Microsoft Entra ID Users**。
2. 确认 `userPrincipalName` 或 `mail` 映射到 SCIM `userName` 属性，并且该属性是用于 **Matching precedence 1** 的属性。
3. 如果存在 `externalId`，请将其从匹配属性中移除。

Tuist 通过 `userName` 匹配预配的用户。它不存储 Entra ID 作为 `externalId` 发送的目录对象标识符，因此对该属性的过滤器找不到现有成员，预配周期可能会出现不可预测的行为。

### 步骤 4：禁用组预配 {#entra-step-4}

在 **Mappings** 下，将 **Provision Microsoft Entra ID Groups** 设置为禁用。

Tuist 的 SCIM 组是每个组织角色的固定组，而不是你可以创建的目录组，因此尝试预配目录组会失败。请改为按照下文所述分配角色。

### 步骤 5：分配用户并开始预配 {#entra-step-5}

1. 打开应用程序的 **Users and groups** 选项卡，并分配应预配到 Tuist 的用户或组。
2. 返回 **Provisioning** 并启动它。
3. 检查 Tuist 的 **Members** 选项卡，验证已分配的用户是否出现在组织中。

Entra ID 按照自己的计划进行预配，通常每 40 分钟一次，因此成员不会立即出现。使用 **Provision on demand** 立即测试单个用户。

要测试取消预配，请在 Entra ID 中取消分配或禁用用户，并验证他们是否从 Tuist 组织的 **Members** 选项卡中消失。

如果你稍后更改预配范围，例如从 **Sync all users and groups** 改为 **Sync only assigned users and groups**，请随后点击 **Restart provisioning**。Entra ID 仅在重启后应用新范围，包括取消预配不再属于该范围的用户。

### 分配角色 {#entra-assigning-administrators}

Tuist 有三个 <.localized_link href="/guides/server/accounts-and-projects#roles">角色</.localized_link>：`admin`、`user` 和 `viewer`。要从 Entra ID 设置它们：

1. 在 **App registrations** 中，打开 Tuist 应用程序，并为你想要分配的每个 Tuist 角色添加一个应用角色。将 **Allowed member types** 设置为 **Users/Groups**，将 **Value** 设置为 `admin`、`user` 或 `viewer`。
2. 在企业应用程序的 **Users and groups** 选项卡上，为每个用户或组分配其中一个应用角色。用户可以拥有多个应用角色。Tuist 应用权限最高的角色，其中 `admin` 高于 `user`，`user` 高于 `viewer`，因此属于映射到不同角色的组的用户将获得其中最高的角色。
3. 在 **Provisioning > Mappings** 下，打开 **Advanced Options** 下拉菜单并选择 **Edit target User attributes**。添加一个名为 `roles` 的属性，将 **Type** 设置为 `String`，并勾选 **Multi-Value**。
4. 在 **Provisioning > Mappings > Provision Microsoft Entra ID Users** 下，点击 **Add New Mapping**。将 **Mapping type** 设置为 **Expression**，将 **Expression** 设置为 `AssertiveAppRoleAssignmentsComplex([appRoleAssignments])`，并将 **Target attribute** 设置为你添加的 `roles` 属性。
5. 保持预配范围设置为 **Sync only assigned users and groups**。`AssertiveAppRoleAssignmentsComplex` 与 **Sync all users and groups** 不兼容。

`AssertiveAppRoleAssignmentsComplex` 发送用户拥有的每个应用角色，并且还会发送移除操作，因此在 Entra ID 中移除角色会将用户降级为他们仍然持有的权限最高的角色。`SingleAppRoleAssignment([appRoleAssignments])` 映射到 `roles[primary eq "True"].value` 也可以工作，但它只发送一个角色，并且当用户拥有多个角色时，Entra ID 不保证会选择哪一个。

在 Entra ID 中更改用户的应用角色会在下一个预配周期更新其 Tuist 角色。预配时没有应用角色，或者值不是 `admin`、`user` 或 `viewer` 的用户，将获得组织注册单点登录成员时的角色，除非管理员在 **Settings > Authentication** 下进行了更改，否则该角色为 `user`。

## 生命周期行为 {#lifecycle-behavior}

当你的身份提供商将用户分配给预配应用程序时，如果 Tuist 尚不知道该电子邮件地址，Tuist 会创建该用户，然后将其添加到组织中。如果该电子邮件地址已属于组织外的现有 Tuist 用户，Tuist 会拒绝该请求，以防止身份提供商声称管理它在该组织中尚未管理的用户。

当你的身份提供商取消分配或停用用户时，Tuist 会移除其组织角色，同时保留用户记录及其拥有的任何工作。取消预配不会全局禁用用户，因为同一个 Tuist 用户可以属于其他组织。

Tuist 公开三个合成 SCIM 组：`Tuist Admins`、`Tuist Users` 和 `Tuist Viewers`。将成员添加到组会设置其组织角色。从与其当前角色匹配的组中移除成员会将其移回注册角色，而成员资格本身仅在用户被取消分配或停用时结束。身份提供商还可以通过用户上的 SCIM `roles` 属性设置角色，值为 `admin`、`user` 或 `viewer`。发送多个值的身份提供商将获得其中权限最高的值，其中 `admin` 高于 `user`，`user` 高于 `viewer`。

## 支持的 SCIM 功能 {#supported-scim-features}

Tuist 支持身份提供商进行生命周期管理所需的 SCIM 2.0 端点：

- `POST`、`GET`、`PUT`、`PATCH` 和 `DELETE` 用于 `/Users`。
- `GET` 和 `PATCH` 用于 `/Groups`。
- `/ServiceProviderConfig`、`/ResourceTypes` 和 `/Schemas` 的 SCIM 发现端点。
