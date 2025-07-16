---
title: SSO
titleTemplate: :title | Integrations | Guides | Tuist
description: Learn how to set up Single Sign-On (SSO) with your organization.
---

# SSO {#sso}

## Google {#google}

Google Workspace 조직이 있고 동일한 Google 도메인으로 로그인하는 개발자가 Tuist 조직에 추가되도록 설정하려면 다음과 같이 설정할 수 있습니다:

```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

> [!IMPORTANT]. 조직의 도메인을 설정하려면 해당 조직에 연결된 이메일을 사용하여 Google에 인증되어 있어야 합니다.

## Okta {#okta}

SSO with Okta is available only for enterprise customers. If you are interested in setting it up, please contact us at [contact@tuist.dev](mailto:contact@tuist.dev).

During the process, you will be assigned a point of contact to help you set up the Okta SSO.

Firstly, you will need to create an Okta application and configure it to work with Tuist:

1. Go to Okta admin dashboard
2. Applications > Applications > Create App Integration
3. Select "OIDC - OpenID Connect" and "Web Application"
4. Enter the display name for the application, for example, "Tuist". Upload a Tuist logo located at [this URL](https://tuist.dev/images/tuist_dashboard.png).
5. Leave sign-in redirect URIs as it is for now
6. Under "Assignments" choose the desired access control to the SSO Application and save.
7. After saving, the general settings for the application will be available. Copy the "Client ID" and "Client Secret" – you will need to safely share this with your point of contact.
8. The Tuist team will need to redeploy the Tuist server with the provided client ID and secret. This may take up to one business day.
9. Once the server is deployed, click on General Settings "Edit" button.
10. Paste the following redirect URL: `https://tuist.dev/users/auth/okta/callback`
11. Change "Login initiated by" to "Either Okta or App".
12. Select "Display application icon to users"
13. Update the "Initiate login URL" with `https://tuist.dev/users/auth/okta?organization_id=1`. The `organization_id` will be supplied by your point of contact.
14. Click "Save".
15. Initiate Tuist login from your Okta dashboard.
16. Give automatically access to your Tuist organization to users signed from your Okta domain by running the following command:

```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

> [!IMPORTANT]
> Users need to initially sign in via their Okta dashboard as Tuist currently doesn't support automatic provisioning and deprovisioning of users from your Okta organization. Once they sign in via their Okta dashboard, they will be automatically added to your Tuist organization.
