---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) and SCIM provisioning with your organization."
}
---
# SSO {#sso}

Tuist offers Single Sign-On (SSO) as a login option to provide additional account security for your organization.

SSO can be configured from the **Authentication** tab in your organization settings. Google and Okta are supported as identity providers. The same page also lets you create SCIM tokens for identity-provider-managed provisioning.

## Google {#google}

Google SSO allows any developer who signs in with a Google Workspace account from your domain to be automatically added to your Tuist organization.

> [!NOTE]
> **Prerequisites**
>
> You need a Google Workspace organization with a verified domain. You must also be authenticated with Google using an email tied to the domain you are setting up.


### Setup

1. Navigate to your organization's **Authentication** settings tab.
2. Enable SSO using the toggle.
3. Select **Google** as the provider.
4. Enter your Google Workspace domain (e.g., `example.com`).
5. Click **Save changes**.

## Okta {#okta}

Okta SSO uses the OIDC protocol to allow members of your Okta organization to sign in to Tuist. Tuist also supports SCIM 2.0 provisioning so Okta can create, update, and deprovision organization members automatically.

SSO and SCIM are configured as two separate Okta applications:

- An **OIDC Web Application** for signing in to Tuist.
- A **SCIM 2.0 Test App (Header Auth)** application for provisioning users and groups into Tuist.

### Step 1: Create an Okta OIDC application {#okta-step-1}

1. In your Okta admin dashboard, go to **Applications > Applications > Create App Integration**.
2. Select **OIDC - OpenID Connect** and **Web Application**.
3. Set the application name (e.g., "Tuist"). Optionally upload the [Tuist logo](https://tuist.dev/images/tuist_dashboard.png).
4. Set the **Sign-in redirect URI** to the value shown on the Authentication settings page (e.g., `https://tuist.dev/users/auth/okta/callback`).
5. Under **Assignments**, choose the desired access control and save.
6. Copy the **Client ID** and **Client Secret** from the application's general settings. Note your **Okta domain** (e.g., `your-company.okta.com`).
7. Optionally, to allow login from the Okta dashboard, click **Edit** on General Settings, change **Login initiated by** to **Either Okta or App**, select **Display application icon to users**, and set the **Initiate login URI** to the value shown on the Authentication settings page (e.g., `https://tuist.dev/users/auth/okta?organization_id=YOUR_ORG_ID`).

### Step 2: Configure Tuist {#okta-step-2}

1. Navigate to your organization's **Authentication** settings tab.
2. Enable Single Sign-On using the toggle.
3. Select **Okta** as the provider.
4. Enter your **Okta domain**, **Client ID**, and **Client Secret**.
5. Click **Save changes**.

### Step 3: Configure Okta SCIM provisioning {#okta-step-3}

1. In Tuist, stay on the organization's **Authentication** settings tab.
2. In the **SCIM provisioning** section, copy the **Base URL**. It should end in `/scim/v2`.
3. Click **Generate token**, name it (for example, `Okta`), and copy the generated token. Tuist shows the token only once.
4. In your Okta admin dashboard, go to **Applications > Applications > Browse App Catalog**.
5. Search for and add **SCIM 2.0 Test App (Header Auth)**. Name it something recognizable, such as `Tuist SCIM`.
6. Complete the sign-on settings for the SCIM test app. Tuist does not use this app for sign-in; sign-in is handled by the OIDC application from step 1.
7. Open the SCIM app's **Provisioning** tab.
8. Under **Settings > Integration**, click **Configure API Integration** or **Edit**.
9. Check **Enable API integration**.
10. Paste the Tuist SCIM base URL into **Base URL**.
11. Paste the Tuist SCIM token into **API Token** prefixed with `Bearer `. For example, `Bearer tuist_scim_...`. Okta sends this field as the `Authorization` header, and Tuist expects a bearer token.
12. Enable **Import Groups** if you want Okta to read Tuist's SCIM groups.
13. Click **Test API Credentials**. Okta should report that the integration was verified successfully.
14. Click **Save**.
15. Under **Settings > To App**, click **Edit** and enable:
    - **Create Users**
    - **Update User Attributes**
    - **Deactivate Users**
16. Click **Save**.
17. Open the **Assignments** tab and assign the users or groups that should be provisioned into Tuist.

When Okta assigns a user to the SCIM app, Tuist creates or reuses the user by email and adds them to the organization. The SCIM app is authoritative for the users assigned to it, so only assign users or groups whose email identities your Okta tenant is allowed to manage. When Okta unassigns or deactivates the user, Tuist removes their organization role and marks the user inactive while preserving the user record and any work they own. Assign the same users or groups to the OIDC application if they should also be able to sign in with SSO.

### Supported SCIM features {#okta-supported-scim-features}

Tuist supports the SCIM 2.0 endpoints Okta needs for lifecycle management:

- `POST`, `GET`, `PUT`, `PATCH`, and `DELETE` for `/Users`.
- `GET` and `PATCH` for `/Groups`.
- SCIM discovery endpoints for `/ServiceProviderConfig`, `/ResourceTypes`, and `/Schemas`.

Tuist exposes two synthetic SCIM groups: `Admins` and `Users`. Group membership changes from Okta map to organization roles in Tuist.

> [!NOTE]
> SCIM provisioning does not replace SSO. SCIM controls membership and lifecycle, while the OIDC application controls login. Once a SCIM-provisioned user signs in through the Okta OIDC application with the same email address, Tuist links that Okta identity to the existing user.
