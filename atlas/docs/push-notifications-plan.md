# Native push notifications

## Research and decision

Atlas uses APNs directly for iOS and Firebase Cloud Messaging (FCM HTTP v1) for Android. Android uses its default Google Play Services transport instead of requiring a separate UnifiedPush distributor app. Firebase is Android-only; no Firebase SDK is included on iOS. PostgreSQL is the registration authority and Oban is the durable delivery queue. No new messaging service, Firebase iOS SDK, marketing platform, or always-running mobile socket is needed.

References consulted:

- [Slack: Into the Clouds](https://slack.engineering/into-the-clouds/): decouple product notification intent from delivery; version payloads and safely ignore unknown types. Do not tie the foundation to chat messages or a particular domain event.
- [Uber: real-time push platform](https://www.uber.com/us/en/blog/real-time-push-platform/): foreground synchronization is a separate problem from operating-system alerts. Atlas already has presence connections; push is not another presence transport.
- [Firebase token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens) and [Firebase's token lifecycle article](https://firebase.blog/posts/2023/04/managing-cloud-messaging-tokens/): refresh registrations with timestamps, retire inactive devices, and distinguish permanent token errors from retryable/configuration errors.
- [FCM error codes](https://firebase.google.com/docs/cloud-messaging/error-codes): a malformed payload must not invalidate every destination token.
- [Apple registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns) and [token-based provider connections](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns): obtain tokens from the OS, request consent, use signed provider credentials and HTTP/2.

These are architecture inputs, not claims that Atlas reproduces a company's private implementation or scale requirements.

## Server plan

1. Bearer-only `PUT /api/me/push-devices/:installation_id` and idempotent JSON `DELETE` at the same route. The authenticated identity supplies the owner. Registration accepts only platform, token and environment, never a user selector or arbitrary app/topic/endpoint.
2. Encrypt provider tokens at rest. Store a non-reversible lookup digest and timestamps. Bind registration to the native OAuth client; account replacement and token movement must invalidate old delivery identities. Deleted installation IDs must not be resurrected by delayed registration requests.
3. Enqueue per-registration jobs carrying IDs, not tokens. Recheck current owner, registration and expiry immediately before sending. Bound retries, honor provider backpressure, and compare the attempted token version before invalidation.
4. APNs uses ES256 provider tokens, a dedicated HTTP/2 transport, explicit sandbox/production routing, expiry and collapse IDs. FCM uses service-account OAuth and HTTP v1. Missing credentials disable only that provider. Credentials never reach clients or build artifacts.
5. Keep lock-screen content generic. Payloads contain versioned navigation intents; app/domain authorization still happens when the record is fetched. Provider acceptance is not a delivery/read receipt. At-least-once retries can duplicate an alert after ambiguous network success.
6. Expose a caller-only, rate-limited MCP self-test and an internal send-to-user API. This foundation does not automatically subscribe every domain event or add an arbitrary-recipient public send endpoint.
7. Document retention, export, deletion, credential provisioning and device smoke tests. No production deployment or credential creation is part of this code change.

## Native plan

- The independent Rust auth crate owns fixed registration routes, validation, bounded HTTPS and response filtering. Swift/Kotlin use the existing refresh/persist coordinator and reject stale session results.
- Opt-in lives in Profile, never in an unsolicited startup permission prompt. Refresh OS tokens on foreground/rotation. OS permission revocation removes server registration.
- Persist installation IDs in device-only encrypted storage. Disable local opt-in on sign-out and attempt remote cleanup before discarding credentials. Preserve per-origin disabled cleanup records for offline sign-out; corrupt push bookkeeping must not block deleting OAuth credentials. Cleanup must not allow a delayed old-session request to enroll the next user. Generic iOS alerts are necessary because the OS can display a queued alert without running the app.
- iOS uses `UIApplicationDelegateAdaptor` and `UNUserNotificationCenterDelegate`, including cold-start taps. Distribution derives the environment from the signed provisioning profile, not debug/release assumptions.
- Android uses the official Firebase SDK with data-only messages and a notification channel. Initialize from public Firebase project identifiers, not service-account credentials. Drop messages when the local registration/session does not match. No Google Play services means unavailable push, not broken login.
- All taps enter the existing origin-bound, allowlisted Atlas destination parser. Unknown payload versions, invalid links and wrong origins never switch servers or trigger mutations.

## Claude review and changes

Claude reviewed the repository and pinned Once 0.68.2 before implementation. Incorporated review points include OAuth-client binding, logout/account-switch cleanup, token-version compare-and-delete, APNs HTTP/2, provider-token reuse, generic iOS content, and expiry-aware jobs.

Android is the main build risk: Once accepts transitive library jars and multidex but does not import Maven AARs or merge manifests automatically. A project-local import must pin the complete artifact closure, audit manifest entries, and generate library-package R classes using the same resource IDs as the APK. Do not substitute a handwritten FCM protocol or claim Android delivery works without validating this integration.

## Validation gates

- Rust fixed-route, input validation, response filtering and stale-session tests.
- Server registration authorization, ownership changes/tombstones, enqueue uniqueness/expiry, retry classification and token-rotation invalidation tests using stubbed transports.
- iOS permission/lifecycle/navigation tests plus simulator build and distribution-profile checks.
- Android dependency integrity, manifest/resource consistency, Kotlin lint and APK build.
- Physical devices: permission allowed/denied, foreground/background/terminated delivery, tap routing, rotation, sign-out/account switch, missing credentials, and disabled OS notifications. These require configured providers and signed device builds and cannot be replaced by stubbed tests.

## Implementation validation

- Server `mix precommit` passes: compilation, dependency checks, Credo, formatting, and 2,903 passing tests (8 doctests and 2,895 tests), with 5 skipped and 1 excluded.
- Native `mise run check` passes through Once for Rust core/authentication/CLI tests. Rust formatting/Clippy, Kotlin lint, and Swift lint pass.
- iOS simulator build and Swift tests pass, including versioned navigation hints, per-origin encrypted registration isolation, cleanup retries, and corrupt/failed push-store fallback. The unsigned iOS device build passes.
- Android builds with the official SDK and the final-APK gate verifies 249 library resource IDs. Portable importer, manifest, APNs provisioning, associated-domain and signing-keychain tests pass.
- These checks do not prove live delivery: provider credentials, Android public project identifiers, a push-authorized Apple signing profile and physical-device lifecycle testing remain required. No production provider configuration or deployment is included.
