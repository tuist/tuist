---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

Tuist offers Single Sign-On (SSO) as a login option to provide additional account security for your organization.

SSO can be configured from the **SSO** tab in your organization settings. Google and Okta are supported as identity providers.

## Google {#google}

Google SSO allows any developer who signs in with a Google Workspace account from your domain to be automatically added to your Tuist organization.

::: info PREREQUISITES
<!-- -->
You need a Google Workspace organization with a verified domain. You must also be authenticated with Google using an email tied to the domain you are setting up.
<!-- -->
:::

### Setup

1. Navigate to your organization's **SSO** settings tab.
2. Enable SSO using the toggle.
3. Select **Google** as the provider.
4. Enter your Google Workspace domain (e.g., `example.com`).
5. Click **Save changes**.

## Okta {#okta}

Okta SSO uses the OIDC protocol to allow members of your Okta organization to sign in to Tuist and be automatically added to your organization.

### Step 1: Create an Okta application {#okta-step-1}

1. In your Okta admin dashboard, go to **Applications > Applications > Create App Integration**.
2. Select **OIDC - OpenID Connect** and **Web Application**.
3. Set the application name (e.g., "Tuist"). Optionally upload the [Tuist logo](https://tuist.dev/images/tuist_dashboard.png).
4. Set the **Sign-in redirect URI** to the value shown on the SSO settings page (e.g., `https://cloud.tuist.dev/users/auth/okta/callback`).
5. Under **Assignments**, choose the desired access control and save.
6. Copy the **Client ID** and **Client Secret** from the application's general settings. Note your **Okta domain** (e.g., `your-company.okta.com`).
7. Optionally, to allow login from the Okta dashboard, click **Edit** on General Settings, change **Login initiated by** to **Either Okta or App**, select **Display application icon to users**, and set the **Initiate login URI** to the value shown on the SSO settings page (e.g., `https://cloud.tuist.dev/users/auth/okta?organization_id=YOUR_ORG_ID`).

### Step 2: Configure Tuist {#okta-step-2}

1. Navigate to your organization's **SSO** settings tab.
2. Enable Single Sign-On using the toggle.
3. Select **Okta** as the provider.
4. Enter your **Okta domain**, **Client ID**, and **Client Secret**.
5. Click **Save changes**.

::: warning
<!-- -->
Users need to initially sign in via their Okta dashboard as Tuist currently doesn't support automatic provisioning and deprovisioning of users. Once they sign in via Okta, they will be automatically added to your Tuist organization.
<!-- -->
:::
