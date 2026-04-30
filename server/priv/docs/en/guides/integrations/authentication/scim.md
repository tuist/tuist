---
{
  "title": "SCIM provisioning",
  "titleTemplate": ":title | Authentication | Integrations | Guides | Tuist",
  "description": "Learn how to configure SCIM provisioning with Okta."
}
---
# SCIM provisioning {#scim-provisioning}

Tuist supports SCIM 2.0 provisioning so an identity provider can create, update, and deprovision organization members automatically.

SCIM is configured from the **Authentication** tab in your organization settings. The SCIM token is an organization-owned account token scoped to SCIM access and is shown only once when generated.

> [!NOTE]
> SCIM controls membership and lifecycle. It does not replace <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>. Configure SSO separately if provisioned users should also sign in through your identity provider.

## Okta {#okta}

Okta uses two separate applications for Tuist:

- An **OIDC Web Application** for signing in to Tuist.
- A **SCIM 2.0 Test App (Header Auth)** application for provisioning users and groups into Tuist.

Configure <.localized_link href="/guides/integrations/authentication/sso#okta">Okta SSO</.localized_link> first if users should sign in with Okta, then configure SCIM provisioning with the steps below.

### Step 1: Generate a Tuist SCIM token {#okta-step-1}

1. In Tuist, navigate to your organization's **Authentication** settings tab.
2. In the **SCIM provisioning** section, copy the **Base URL**. It should end in `/scim/v2`.
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
4. Paste the Tuist SCIM base URL into **Base URL**.
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

## Lifecycle behavior {#lifecycle-behavior}

When Okta assigns a user to the SCIM app, Tuist creates or reuses the user by email and adds them to the organization. The SCIM app is authoritative for the users assigned to it, so only assign users or groups whose email identities your Okta tenant is allowed to manage.

When Okta unassigns or deactivates the user, Tuist removes their organization role and marks the user inactive while preserving the user record and any work they own. If the user is provisioned again later, Tuist marks the user active again.

Tuist exposes two synthetic SCIM groups: `Admins` and `Users`. Group membership changes from Okta map to organization roles in Tuist.

## Supported SCIM features {#supported-scim-features}

Tuist supports the SCIM 2.0 endpoints Okta needs for lifecycle management:

- `POST`, `GET`, `PUT`, `PATCH`, and `DELETE` for `/Users`.
- `GET` and `PATCH` for `/Groups`.
- SCIM discovery endpoints for `/ServiceProviderConfig`, `/ResourceTypes`, and `/Schemas`.
