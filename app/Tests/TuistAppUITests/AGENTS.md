# iOS UI Automation

Use the `TuistApp-iOS` scheme with an explicit iOS Simulator destination. XCUITest requires XCTest; do not replace these tests with Swift Testing.

- `AdaptiveSignInTests` requires a signed-out simulator and checks that all sign-in actions remain reachable after rotation and at accessibility text sizes.
- `SignedInPagesTests` is a live-account screenshot check. Sign in to the demo account before running it; it expects access to `tuist/wikipedia`. It skips without that session or project. It captures the previews list, a preview detail, and profile without running an app preview or changing account data. Run it explicitly with `-only-testing:TuistAppUITests/SignedInPagesTests`.
- Never put account passwords, access tokens, or refresh tokens in test sources, screenshot manifests, or PR attachments. Use the app's existing debug email/password launch options to sign in with credentials supplied by the user.
- Sign simulator builds when testing real authentication. An unsigned build can render screens while Keychain credential storage fails. Ad-hoc simulator signing uses `CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=-`; it does not require a distribution certificate.
- Keep screenshot attachments with `.keepAlways`. Export them with `xcrun xcresulttool export attachments --path RESULTS.xcresult --output-path OUTPUT` and inspect the images before using them in a PR. An orientation request alone is not proof that the rendered display rotated.
- Reuse the requested simulator, disable parallel UI testing, and do not create or boot extra devices for screenshot capture. Duo's outer and inner displays belong to one device; capture the active display, not an inactive black framebuffer.
