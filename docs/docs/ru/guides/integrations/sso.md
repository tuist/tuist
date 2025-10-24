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
   Copy the "Client ID" and "Client Secret" – you will need to safely share this
   with your point of contact.
8. The Tuist team will need to redeploy the Tuist server with the provided
   client ID and secret. This may take up to one business day.
9. Once the server is deployed, click on General Settings "Edit" button.
10. Paste the following redirect URL:
    `https://tuist.dev/users/auth/okta/callback`
13. Change "Login initiated by" to "Either Okta or App".
14. Select "Display application icon to users"
15. Update the "Initiate login URL" with
    `https://tuist.dev/users/auth/okta?organization_id=1`. The `organization_id`
    will be supplied by your point of contact.
16. Click "Save".
17. Initiate Tuist login from your Okta dashboard.
18. Give automatically access to your Tuist organization to users signed from
    your Okta domain by running the following command:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
Users need to initially sign in via their Okta dashboard as Tuist currently
doesn't support automatic provisioning and deprovisioning of users from your
Okta organization. Once they sign in via their Okta dashboard, they will be
automatically added to your Tuist organization.
<!-- -->
:::
