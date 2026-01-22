---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

If you have a Google Workspace organization and you want any developer who signs
in with the same Google hosted domain to be added to your Tuist organization,
you can set it up with:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
You must be authenticated with Google using an email tied to the organization
whose domain you are setting up.
<!-- -->
:::

## Okta {#okta}

SSO with Okta is available only for enterprise customers. If you are interested
in setting it up, please contact us at
[contact@tuist.dev](mailto:contact@tuist.dev).

During the process, you will be assigned a point of contact to help you set up
the Okta SSO.

Firstly, you will need to create an Okta application and configure it to work
with Tuist:
1. Go to Okta admin dashboard
2. Applications > Applications > Create App Integration
3. Select "OIDC - OpenID Connect" and "Web Application"
4. Enter the display name for the application, for example, "Tuist". Upload a
   Tuist logo located at [this
   URL](https://tuist.dev/images/tuist_dashboard.png).
5. Leave sign-in redirect URIs as it is for now
6. Under "Assignments" choose the desired access control to the SSO Application
   and save.
7. After saving, the general settings for the application will be available.
   Copy the "Client ID" and "Client Secret". Also note your Okta organization
   URL (e.g., `https://your-company.okta.com`) – you will need to safely share
   all of these with your point of contact.
8. Once the Tuist team has configured the SSO, click on General Settings "Edit"
   button.
9. Paste the following redirect URL:
   `https://tuist.dev/users/auth/okta/callback`
10. Change "Login initiated by" to "Either Okta or App".
11. Select "Display application icon to users"
12. Update the "Initiate login URL" with
    `https://tuist.dev/users/auth/okta?organization_id=1`. The `organization_id`
    will be supplied by your point of contact.
13. Click "Save".
14. Initiate Tuist login from your Okta dashboard.

::: warning
<!-- -->
Users need to initially sign in via their Okta dashboard as Tuist currently
doesn't support automatic provisioning and deprovisioning of users from your
Okta organization. Once they sign in via their Okta dashboard, they will be
automatically added to your Tuist organization.
<!-- -->
:::
