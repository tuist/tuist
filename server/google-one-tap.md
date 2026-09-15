# Google One Tap

Signed-out visitors to marketing, login and sign-up pages can sign in with Google's browser-mediated account chooser. Chrome renders the prompt through [Federated Credential Management](https://developer.chrome.com/docs/identity/fedcm). Google and the browser decide whether to display it, depending on the visitor's Google session, browser support, permissions and dismissal history. Automatic account selection is disabled.

## Configuration

The integration reuses `TUIST_GOOGLE_OAUTH_CLIENT_ID` and `TUIST_GOOGLE_OAUTH_CLIENT_SECRET` from the existing Google sign-in configuration. `TUIST_GOOGLE_AUTH_ENABLED=0` disables both ordinary Google sign-in and One Tap.

In the Google Auth Platform console, select the existing web application client and add each site's origin, including its scheme, to **Authorized JavaScript origins**. For local testing, authorize both `http://localhost` and the development server's exact origin, such as `http://localhost:8888`. Production origins must use encrypted connections. See [Google's setup guide](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid).

One Tap submits credentials from a JavaScript callback to Tuist's own form endpoint. It does not require adding that endpoint to Google's authorized redirect addresses. Keep the existing redirect address for ordinary Google sign-in.

## Authentication

The shared hook checks browser support before contacting Google. A protected `POST /auth/google/one-tap/start` issues a random nonce and stores a five-minute challenge in the browser session. The response is marked `private, no-store`, so shared marketing caches cannot distribute a visitor's challenge.

Google returns a signed identity token containing that nonce. The hook submits it to `POST /auth/google/one-tap`, with Tuist's existing cross-site request forgery protection. The server consumes the challenge, verifies Google's signature and identity claims, and uses the existing login or username-selection flow. Google Workspace's hosted domain is preserved. For an unlinked account whose email Google does not host, the integration falls back to ordinary Google sign-in.

Credentials are filtered from request logs and are not persisted. Public Google signing keys are cached for at most five minutes, respecting their remaining advertised cache lifetime. No new database records or profile fields are introduced beyond the existing Google identity and account records.

On login and sign-up screens, the hook follows the LiveView lifecycle and cancels pending sign-in on navigation. The authentication live session allows Google resources on its initial response so navigating from password reset to login can initialize the chooser without a full page reload. Only login and sign-up mount the prompt within that session.

## Verification

Run `mix test test/tuist/oauth/google_test.exs test/tuist_web/controllers/google_one_tap_test.exs` for token validation, session handling, account linking and configuration gates.

To verify the actual browser chooser, visit the marketing, login and sign-up pages on an authorized origin in Chrome while signed into Google. Navigate between login and sign-up using their links, and from password reset back to login, to verify the prompt follows navigation. Confirm account selection signs in an existing user or opens username selection for a new user. Confirm dismissing the chooser leaves the page usable. Browsers without native identity credential support retain the existing login links.

Browser tests using a mocked Google library can verify initialization and credential submission, but they do not validate Google's origin registration or the native account chooser. Headless page screenshots capture page content, not Chrome's browser-owned dialog.
