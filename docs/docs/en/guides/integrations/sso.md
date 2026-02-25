---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

You can configure Single Sign-On (SSO) for your organization from the **SSO** tab in your organization settings. Both Google and Okta SSO can be set up directly from the dashboard without contacting support.

## Google {#google}

If you have a Google Workspace organization and you want any developer who signs in with the same Google hosted domain to be added to your Tuist organization:

1. Navigate to your organization's **SSO** settings tab.
2. Enter your Google Workspace domain (e.g., `my-google-domain.com`).
3. Click **Enable Google SSO**.

::: warning
<!-- -->
You must be authenticated with Google using an email tied to the organization whose domain you are setting up.
<!-- -->
:::

Alternatively, you can set it up via the CLI:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

## Okta {#okta}

You can set up Okta SSO directly from the dashboard:

### Step 1: Create an Okta application

1. Go to your Okta admin dashboard.
2. Navigate to Applications > Applications > Create App Integration.
3. Select "OIDC - OpenID Connect" and "Web Application".
4. Enter the display name for the application, for example, "Tuist". Optionally upload a Tuist logo located at [this URL](https://tuist.dev/images/tuist_dashboard.png).
5. Set the sign-in redirect URI to the value shown on the SSO settings page (e.g., `https://tuist.dev/users/auth/okta/callback`).
6. Under "Assignments" choose the desired access control to the SSO Application and save.
7. After saving, copy the **Client ID** and **Client Secret** from the application's general settings. Also note your Okta domain (e.g., `your-company.okta.com`).

### Step 2: Configure Tuist

1. Navigate to your organization's **SSO** settings tab.
2. Enter your **Okta domain**, **Client ID**, and **Client Secret**.
3. Click **Enable Okta SSO**.

### Step 3: Configure Okta-initiated login (optional)

1. In your Okta application settings, click "Edit" on General Settings.
2. Change "Login initiated by" to "Either Okta or App".
3. Select "Display application icon to users".
4. Set the "Initiate login URI" to the value shown on the SSO settings page (e.g., `https://tuist.dev/users/auth/okta?organization_id=YOUR_ORG_ID`).
5. Click "Save".

::: warning
<!-- -->
Users need to initially sign in via their Okta dashboard as Tuist currently doesn't support automatic provisioning and deprovisioning of users from your Okta organization. Once they sign in via their Okta dashboard, they will be automatically added to your Tuist organization.
<!-- -->
:::
