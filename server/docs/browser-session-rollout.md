# Browser session isolation rollout

The compatibility release reads legacy session and remember-me cookies as well as the dedicated authentication cookie. No token migration or forced sign-out is needed. Database expiry, revocation and MFA checks remain authoritative.

## Deploy readers before enabling writers

1. Deploy this release to **every web replica** with `TUIST_BROWSER_SESSION_ISOLATION_ENABLED` unset or `false`. In this mode, browsers without an authentication cookie continue using the ordinary session credential, and One Tap starts use the legacy aggregate cookie. Old replicas can still complete those flows.
2. Confirm that all web replicas run this release and no pre-compatibility replica can receive traffic. Allow in-flight requests on retired replicas to drain before activation.
3. Set `TUIST_BROWSER_SESSION_ISOLATION_ENABLED=true`. Only the exact string `true` activates issuance. Subsequent explicit authentication actions establish the dedicated credential cookie; ordinary reads do not migrate existing sessions. One Tap starts now issue independent challenge cookies. Existing aggregate challenges can still complete until their one-hour expiry.

The default-off stage deliberately retains legacy credential and aggregate-challenge races until activation. It is a compatibility stage, not full mitigation.

## Rollback boundary

After activation, the oldest supported rollback target is **this compatibility release**, even if the flag is disabled. A compatible replica always reads and updates an authentication cookie already present, and can complete both One Tap formats. Disabling the flag stops first issuance, not existing authority reads or updates. It does not return existing browsers to legacy credential authority.

Do not roll back to a pre-compatibility binary after activation. Such a binary cannot update dedicated credentials on login or MFA rotation and cannot complete independent One Tap challenges. Ordinary-session credential mirrors do not make that rollback safe. Keep a compatibility-capable rollback image available before activating.

## OAuth attempts across the upgrade

New provider states carry `tuist-return-v1:` plus the provider-generated random state. The redirect and CSRF cookie carry the same state; provider state validation remains mandatory. A signed per-state cookie binds the destination. Missing or invalid bindings on versioned attempts fall back to the normal signed-in page, never another tab's destination.

Pre-upgrade unversioned callbacks without a binding retain their validated legacy session destination. They necessarily retain the old shared-destination limitation. The prefix is not an authentication credential or a substitute for state validation.

The upstream single `ueberauth.state_param` cookie still prevents two simultaneous full-page OAuth attempts from both succeeding. This change does not weaken that CSRF protection or prove the cause of the historical customer incident.

## Regression coverage

`authentication_test.exs`, `google_one_tap_test.exs` and `auth_controller_test.exs` tag mixed-version cases with `:session_compatibility`. They exercise real signed cookie/session formats and database tokens, simulating legacy writers/readers and compatible/enabled modes in one test runtime. Google identity exchange alone is stubbed in callback tests. These tests do not represent a deployed two-binary cluster or a Safari QR-to-Google capture.
