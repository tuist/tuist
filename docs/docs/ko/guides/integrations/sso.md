---
title: SSO
titleTemplate: :title | Integrations | Guides | Tuist
description: Learn how to set up Single Sign-On (SSO) with your organization.
---

# SSO {#sso}

If you have a Google Workspace organization and you want any developer who signs in with the same Google hosted domain to be added to your Tuist organization, you can set it up with:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

For on-premise customers that have Okta set up, you can get the same behavior as for Google by running:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

> [!IMPORTANT]
> You must be authenticated with Google using an email tied to the organization whose domain you are setting up.