---
{
  "title": "SCIM provisioning",
  "titleTemplate": ":title | Authentication | Integrations | Guides | Tuist",
  "description": "Learn how to configure SCIM provisioning with Okta or Microsoft Entra ID."
}
---
# SCIM provisioning {#scim-provisioning}

Tuist supports SCIM 2.0 provisioning so an identity provider can create, update, and deprovision organization members automatically.

SCIM is configured from the **Authentication** tab in your organization settings. The SCIM token is an organization-owned account token scoped to SCIM access and is shown only once when generated.

> [!NOTE]
> SCIM controls membership and lifecycle. It does not replace <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>. Configure SSO separately if provisioned users should also sign in through your identity provider.

Provisioned users are already organization members. When they sign in with the same email address, that membership can establish trust for linking their provider identity. The <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">verified login email domain</.localized_link> and <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">enrollment policy</.localized_link> control users who have not already been provisioned or added to the organization.

## Okta {#okta}

Okta uses two separate applications for Tuist:

- An **OIDC Web Application** for signing in to Tuist.
- A **SCIM 2.0 Test App (Header Auth)** application for provisioning users and groups into Tuist.

Configure <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> first if users should sign in with Okta, then configure SCIM provisioning with the steps below.

### Step 1: Generate a Tuist SCIM token {#okta-step-1}

1. In Tuist, navigate to your organization's **Authentication** settings tab.
2. In the **SCIM provisioning** section, copy the **SCIM endpoint URL**. It should end in `/scim/v2`.
3. Click **Generate token**.
4. Name the token (for example, `Okta`).
5. Copy the generated token. Tuist shows the token only once.

### Step 2: Add the Okta SCIM app {#okta-step-2}

1. In your Okta admin dashboard, go to **Applications > Applications > Browse App Catalog**.
2. Search for and add **SCIM 2.0 Test App (Header Auth)**.
3. Name it something recognizable, such as `Tuist SCIM`.
4. Complete the sign-on settings for the SCIM test app. Tuist does not use this app for sign-in; sign-in is handled by the OIDC application from the SSO guide.

### Step 3: Configure the API integration {#okta-step-3}

1. Open the SCIM app's **Provisioning** tab.
2. Under **Settings > Integration**, click **Configure API Integration** or **Edit**.
3. Check **Enable API integration**.
4. Paste the Tuist **SCIM endpoint URL** into Okta's **Base URL** field.
5. Paste the Tuist SCIM token into **API Token** prefixed with `Bearer `. For example, `Bearer tuist_scim_...`. Okta sends this field as the `Authorization` header, and Tuist expects a bearer token.
6. Enable **Import Groups** if you want Okta to read Tuist's SCIM groups.
7. Click **Test API Credentials**. Okta should report that the integration was verified successfully.
8. Click **Save**.

### Step 4: Enable provisioning actions {#okta-step-4}

1. In the SCIM app's **Provisioning** tab, open **Settings > To App**.
2. Click **Edit**.
3. Enable:
   - **Create Users**
   - **Update User Attributes**
   - **Deactivate Users**
4. Click **Save**.

### Step 5: Assign users or groups {#okta-step-5}

1. Open the SCIM app's **Assignments** tab.
2. Assign the users or groups that should be provisioned into Tuist.
3. Assign the same users or groups to the Okta OIDC application if they should also be able to sign in with SSO.
4. Check Tuist's **Members** tab to verify that assigned users appear in the organization.

To test deprovisioning, unassign or deactivate a user in Okta and verify that they disappear from the Tuist organization's **Members** tab.

### Assigning roles {#okta-assigning-roles}

Tuist has three <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link>: `admin`, `user`, and `viewer`. Tuist exposes one SCIM group per role: `Tuist Admins`, `Tuist Users`, and `Tuist Viewers`. Map Okta groups to them with **Group Push**:

1. Pick or create an Okta group for each role you want to assign, and assign those groups on the SCIM app's **Assignments** tab.
2. Make sure **Import Groups** is enabled in the API integration, then open the SCIM app's **Import** tab and click **Import Now** so that Okta knows about Tuist's groups.
3. Open the SCIM app's **Push Groups** tab and click **Push Groups > Find groups by name**.
4. Select an Okta group, choose **Link Group** as the push action, and pick the matching Tuist group. Tuist doesn't support creating groups through SCIM, so link to an existing group instead of creating a new one.
5. Click **Save** and repeat for the remaining roles.

Adding a user to a linked group gives them that role. Removing them from the group moves them back to the role the organization enrolls single sign-on members at, which is `user` unless an administrator changed it under **Settings > Authentication**. Users who aren't in any linked group get that role too. Removing a user from a group doesn't remove them from the organization; unassign or deactivate them in Okta to do that.

## Microsoft Entra ID {#microsoft-entra-id}

Entra ID provisions Tuist through a non-gallery enterprise application. Configure <.localized_link href="/guides/integrations/authentication/sso#microsoft-entra-id">Microsoft Entra ID SSO</.localized_link> first if users should also sign in with Entra ID.

The application you register for single sign-on and the enterprise application you use for provisioning can be the same one. Provisioning is configured on the enterprise application entry.

### Step 1: Generate a Tuist SCIM token {#entra-step-1}

1. In Tuist, navigate to your organization's **Authentication** settings tab.
2. In the **SCIM provisioning** section, copy the **SCIM endpoint URL**. It should end in `/scim/v2`.
3. Click **Generate token**.
4. Name the token (for example, `Entra ID`).
5. Copy the generated token. Tuist shows the token only once.

### Step 2: Configure provisioning {#entra-step-2}

1. In the Microsoft Entra admin center, go to **Identity > Applications > Enterprise applications** and open the Tuist application.
2. Open **Provisioning** and set **Provisioning Mode** to **Automatic**.
3. Set **Tenant URL** to the Tuist SCIM endpoint URL.
4. Set **Secret Token** to the Tuist SCIM token. Enter the token on its own, without a `Bearer ` prefix; Entra ID adds the scheme itself.
5. Click **Test Connection**. Entra ID should report that the supplied credentials are authorized.
6. Save the configuration.

### Step 3: Set the matching attribute {#entra-step-3}

1. Under **Mappings**, open **Provision Microsoft Entra ID Users**.
2. Confirm that `userPrincipalName` or `mail` maps to the SCIM `userName` attribute, and that this attribute is the one used for **Matching precedence 1**.
3. Remove `externalId` from the matching attributes if it is present.

Tuist matches provisioned users by `userName`. It does not store the directory object identifier that Entra ID sends as `externalId`, so a filter on that attribute does not find an existing member and provisioning cycles can behave unpredictably.

### Step 4: Disable group provisioning {#entra-step-4}

Under **Mappings**, set **Provision Microsoft Entra ID Groups** to disabled.

Tuist's SCIM groups are a fixed group per organization role rather than directory groups you can create, so an attempt to provision a directory group fails. Assign roles as described below instead.

### Step 5: Assign users and start provisioning {#entra-step-5}

1. Open the application's **Users and groups** tab and assign the users or groups that should be provisioned into Tuist.
2. Return to **Provisioning** and start it.
3. Check Tuist's **Members** tab to verify that assigned users appear in the organization.

Entra ID provisions on its own schedule, which is typically every 40 minutes, so members do not appear instantly. Use **Provision on demand** to test a single user immediately.

To test deprovisioning, unassign or disable a user in Entra ID and verify that they disappear from the Tuist organization's **Members** tab.

If you later change the provisioning scope, for example from **Sync all users and groups** to **Sync only assigned users and groups**, click **Restart provisioning** afterwards. Entra ID applies the new scope, including deprovisioning users who are no longer in it, only after a restart.

### Assigning roles {#entra-assigning-administrators}

Tuist has three <.localized_link href="/guides/server/accounts-and-projects#roles">roles</.localized_link>: `admin`, `user`, and `viewer`. To set them from Entra ID:

1. In **App registrations**, open the Tuist application and add an app role for each Tuist role you want to assign. Set **Allowed member types** to **Users/Groups** and **Value** to `admin`, `user`, or `viewer`.
2. On the enterprise application's **Users and groups** tab, assign each user or group one of those app roles. Give each user a single app role; if a user has more than one, Entra ID does not guarantee which one it sends.
3. Under **Provisioning > Mappings > Provision Microsoft Entra ID Users**, click **Add New Mapping**. Set **Mapping type** to **Expression**, **Expression** to `SingleAppRoleAssignment([appRoleAssignments])`, and **Target attribute** to `roles[primary eq "True"].value`.
4. Keep the provisioning scope set to **Sync only assigned users and groups**. `SingleAppRoleAssignment` isn't compatible with **Sync all users and groups**.

Changing a user's app role in Entra ID updates their Tuist role on the next provisioning cycle. A user provisioned without an app role, or with a value other than `admin`, `user`, or `viewer`, gets the role the organization enrolls single sign-on members at, which is `user` unless an administrator changed it under **Settings > Authentication**.

## Lifecycle behavior {#lifecycle-behavior}

When your identity provider assigns a user to the provisioning application, Tuist creates the user if the email is not already known to Tuist, then adds them to the organization. If the email already belongs to an existing Tuist user outside the organization, Tuist rejects the request to prevent an IdP from claiming a user that it does not already manage in that organization.

When your identity provider unassigns or deactivates the user, Tuist removes their organization role while preserving the user record and any work they own. Deprovisioning does not disable the user globally, because the same Tuist user can belong to other organizations.

Tuist exposes three synthetic SCIM groups: `Tuist Admins`, `Tuist Users`, and `Tuist Viewers`. Adding a member to a group sets their organization role. Removing a member from the group that matches their current role moves them back to the enrollment role, and membership itself only ends when the user is unassigned or deactivated. Identity providers can also set the role through the SCIM `roles` attribute on a user, with a value of `admin`, `user`, or `viewer`.

## Supported SCIM features {#supported-scim-features}

Tuist supports the SCIM 2.0 endpoints identity providers need for lifecycle management:

- `POST`, `GET`, `PUT`, `PATCH`, and `DELETE` for `/Users`.
- `GET` and `PATCH` for `/Groups`.
- SCIM discovery endpoints for `/ServiceProviderConfig`, `/ResourceTypes`, and `/Schemas`.
