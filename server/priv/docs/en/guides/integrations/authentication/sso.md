---
{
  "title": "Single Sign-On",
  "titleTemplate": ":title | Authentication | Integrations | Guides | Tuist",
  "description": "Learn how to configure single sign-on, verify a login email domain, and choose how users join your organization."
}
---
# Single Sign-On {#single-sign-on}

Tuist offers single sign-on as a login option to provide additional account security for your organization.

Single sign-on is configured from the **Authentication** tab in your organization settings. Google Workspace, Okta, and custom [OAuth 2.0](https://oauth.net/2/) providers are supported.

> [!NOTE]
> Single sign-on controls how members authenticate and whether authenticated users may join automatically. <.localized_link href="/guides/integrations/authentication/scim">System for Cross-domain Identity Management provisioning</.localized_link> controls whether an identity provider can create, update, and deprovision organization members. For Okta, most organizations configure both.

## How access works {#how-access-works}

Provider identity, login discovery, and organization enrollment are separate concerns:

- **Provider issuer:** The provider organization or authorization server that authenticated the user. Tuist combines the provider, issuer, and stable provider user identifier when looking up a linked identity. For Okta, the issuer is represented by the Okta domain. For a custom provider, it is represented by the provider URL.
- **Login email domain:** The email domain that Tuist uses to discover an Okta or custom provider from the general login page. Once verified, it also establishes which email addresses may be trusted for new account linking and automatic enrollment.
- **Enrollment policy:** Determines whether a user from the trusted domain needs an invitation or may join automatically.
- **Provisioning:** Creates and manages organization membership independently of the login flow.

The provider issuer and login email domain are often different. For example, a company may use `example.com` for employee email while its provider issuer is `https://login.vendor.example.net`. New Okta and custom-provider configurations store these values separately.

### Verify a login email domain {#verify-a-login-email-domain}

Okta and custom providers require a verified login email domain before they can create a new Tuist account or link an existing account that is not already an organization member.

1. Enter the employee email domain, such as `example.com`, in **Login email domain**.
2. Save the single sign-on configuration.
3. Add the text record shown by Tuist to the domain's [Domain Name System](https://www.cloudflare.com/learning/dns/dns-records/dns-txt-record/) configuration.
4. Return to the Authentication settings and click **Verify domain**.

A verified login email domain can belong to only one Tuist organization. Changing the domain clears its verification and requires publishing the new text record. Automatic enrollment remains unavailable until the new domain is verified.

Google Workspace does not require this separate Tuist verification step because Google supplies the verified Workspace domain as part of the authenticated identity.

### Choose an enrollment policy {#choose-an-enrollment-policy}

Tuist supports two enrollment policies:

- **Invitation only:** A user needs an organization invitation. For Okta and custom providers, the login email domain must still be verified before the provider can create a brand-new Tuist account. An existing Tuist user who is already an organization member may link the provider identity based on that membership.
- **Automatic:** A user whose authenticated email matches the trusted domain can create or link an account and join the organization without an invitation. Google configurations use the Workspace domain. Okta and custom providers require a verified login email domain.

Google configurations default to automatic enrollment. New Okta and custom-provider configurations default to invitation-only enrollment.

The **Enforce single sign-on** setting is independent of enrollment. Enforcement prevents existing organization members from using email and password; it does not grant organization membership.

### Existing organizations {#existing-organizations}

Organizations configured before login email domains were introduced retain access for existing accounts:

- Existing linked identities continue signing in.
- Existing organization members may link their Okta or custom-provider identity because membership already establishes trust.
- Existing Google configurations retain automatic enrollment.
- Existing Okta and custom-provider configurations retain their current login discovery and enforcement behavior while their provider configuration remains unchanged.

For existing Okta and custom-provider organizations, automatic enrollment is disabled until an administrator adds and verifies a login email domain. A verified domain is also required before the provider can create a brand-new Tuist account, including for an invited user.

Changing the provider or provider organization identifier stops using the previously inferred email domain. Verify the login email domain before making that change, particularly when single sign-on enforcement is enabled.

## Google Workspace {#google}

Google Workspace single sign-on authenticates users against a Workspace domain. Administrators can allow matching users to join automatically or require an invitation.

> [!NOTE]
> **Prerequisites**
>
> You need a Google Workspace organization with a verified domain. You must also be authenticated with Google using an email tied to the domain you are setting up.

### Setup {#google-setup}

1. Navigate to your organization's **Authentication** settings tab.
2. Enable single sign-on.
3. Select **Google** as the provider.
4. Enter your Google Workspace domain, such as `example.com`.
5. Choose **Automatic enrollment** or invitation-only enrollment. Automatic enrollment is enabled by default for Google.
6. Optionally enable **Enforce single sign-on** after testing the login flow.
7. Click **Save changes**.

## Okta {#okta}

Okta uses [OpenID Connect](https://openid.net/developers/how-connect-works/) to authenticate members. The Okta domain identifies the provider issuer; the separately verified login email domain controls discovery, new account linking, and enrollment.

If you also want Okta to create, update, or deprovision members automatically, configure <.localized_link href="/guides/integrations/authentication/scim#okta">Okta System for Cross-domain Identity Management provisioning</.localized_link> after single sign-on is working.

### Step 1: Create an Okta application {#okta-step-1}

1. In your Okta admin dashboard, go to **Applications > Applications > Create App Integration**.
2. Select **OpenID Connect** and **Web Application**.
3. Set the application name, such as `Tuist`. Optionally upload the [Tuist logo](https://tuist.dev/images/tuist_dashboard.png).
4. Set the **Sign-in redirect URI** to the value shown on the Authentication settings page, such as `https://tuist.dev/users/auth/okta/callback`.
5. Under **Assignments**, choose the desired access control and save.
6. Copy the **Client ID** and **Client Secret** from the application's general settings. Note your **Okta domain**, such as `your-company.okta.com`.
7. Optionally, to allow login from the Okta dashboard, click **Edit** on General Settings, change **Login initiated by** to **Either Okta or App**, select **Display application icon to users**, and set the **Initiate login URI** to the value shown on the Authentication settings page.

### Step 2: Configure Tuist {#okta-step-2}

1. Navigate to your organization's **Authentication** settings tab.
2. Enable single sign-on.
3. Select **Okta** as the provider.
4. Enter the **Okta domain**, **Client ID**, and **Client Secret**.
5. Enter the employee email domain under **Login email domain**. For example, an Okta domain of `your-company.okta.com` may have a login email domain of `example.com`.
6. Click **Save changes**.
7. Add the text record shown by Tuist to the login email domain, then click **Verify domain**.
8. Choose whether users need an invitation or may enroll automatically, then save the configuration again.
9. Optionally enable **Enforce single sign-on** after testing the login flow.

### Step 3: Assign users to the Okta application {#okta-step-3}

Assign the users or groups that should be allowed to authenticate through the Okta application.

Assignment grants access to the login flow, but organization membership still follows the enrollment policy. If the same users are provisioned through System for Cross-domain Identity Management, Tuist links the Okta identity to the existing organization member the first time the user signs in with the same email address.

## Custom OAuth 2.0 provider {#custom-oauth-2-provider}

A custom OAuth 2.0 provider allows an organization to use an identity service other than Google Workspace or Okta. The provider's user information endpoint must return a stable user identifier and an email address.

1. In the provider, create an OAuth 2.0 web application.
2. Set the **Sign-in redirect URI** and optional **Initiate login URI** to the values shown in Tuist's Authentication settings.
3. In Tuist, enable single sign-on and select **OAuth2**.
4. Enter the provider URL, authorization endpoint, token endpoint, user information endpoint, client identifier, and client secret.
5. Enter and save the **Login email domain**. This is the employee email domain, not the provider URL.
6. Add the text record shown by Tuist to the login email domain, then click **Verify domain**.
7. Choose invitation-only or automatic enrollment and save the configuration.
8. Test sign-in before optionally enabling **Enforce single sign-on**.

The provider URL scopes identities to the issuing provider. The verified login email domain determines which email addresses Tuist may trust when linking or enrolling users.

## Command-line configuration {#command-line-configuration}

The command-line interface can configure Google Workspace or Okta and select an enrollment policy. For example:

```bash
tuist organization update sso example \
  --provider okta \
  --organization-id your-company.okta.com \
  --enrollment-policy invitation-only
```

The `--organization-id` value identifies the provider organization. It is not the login email domain. Add and verify the login email domain from the organization's Authentication settings before enrolling new Okta users.

## Troubleshooting {#troubleshooting}

### Existing members can sign in, but new users cannot {#existing-members-can-sign-in-but-new-users-cannot}

For Okta and custom providers, confirm that the login email domain is verified. Then either invite the user or enable automatic enrollment. A brand-new Tuist account cannot be created through these providers before domain verification, even when an invitation exists.

### Tuist cannot find an organization for an email address {#tuist-cannot-find-an-organization-for-an-email-address}

Confirm that the user entered the expected employee email address and that its domain exactly matches the verified login email domain. Existing members may also be discovered through their current organization membership.

### Domain verification remains pending {#domain-verification-remains-pending}

Confirm that the text record name and value exactly match the values shown in Tuist. Domain Name System changes can take time to propagate, so retry verification after the record is publicly available.

### Sign-in stopped after changing the provider {#sign-in-stopped-after-changing-the-provider}

Changing the provider or provider organization identifier stops using the previously inferred email domain. Confirm the new provider configuration, verify the login email domain, and test the login flow before enabling enforcement.
