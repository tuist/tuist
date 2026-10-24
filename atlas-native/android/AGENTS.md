# Atlas Android

This app uses Kotlin platform widgets, not Compose or Gradle. Rust owns navigation,
OAuth, Orbit session state, JSON-schema projection and allowlisted networking. Preserve the package/JNI
names and the existing Once arm64/API-26 build boundary.

`AtlasApplication.kt` defines the single Application class, initializes optional Firebase
configuration, and owns one authentication coordinator across activities. Do not define
another Application in push or activity sources. Its credential
worker serializes secure storage and refresh; HTTP and watch operations use separate
bounded pools so old watch waits cannot block credential changes or mutations. Skip
queued requests from inactive/changed views; reset in-flight UI state on stop.
Fence prepared requests, credential writes and callbacks by session generation. Listener
cleanup must only remove the activity's own listener, never the newly started activity's
listener. Keep opaque sessions and uncertain launch payloads encrypted with Android
Keystore-backed AES-GCM, never plaintext preferences or logs.

`AtlasAutomationActivity` renders workflows, personal activity, assigned approvals and
execution steps. Preserve form revision/values across configuration changes and browser
round trips. Freeze an attempted request and reuse its UUID on uncertain retries. Exact
approval payload/digest confirmation is mandatory. Required nested objects, false, zero
and omission must stay distinct; unsupported schemas offer browser fallback.

Stop following when the activity stops, discard late callbacks, and reconcile the
current execution on return or WebSocket failure. Never imply a background socket keeps
a workflow running: server state does that. Automation execution/approval updates do
not use FCM/background notifications; the separate native push coordinator handles
other fixed notification kinds.
Results are fetched separately and oversized results stay on the protected web page.

The bundled NSH thread-card host passes selected-theme text, secondary text, surface,
border and tint tokens for both `result_table` and `account_card` v1. Rust validates
types and source actions; Android never derives account fields from tool output.
Unsupported runtimes retain the server's text fallback.

Orbit links use the fixed shared capability appended at index 6 (`orbit`, records,
browser fallback `/`, record prefix `/open/orbit`), with canonical sharing and the
only claimed HTTPS Orbit links at `/open/orbit[/<uuid>]`. There is no Orbit web view;
never parse or claim `/` as an equivalent native destination, nor invent `/orbit` routes.
`MainActivity` routes them through the same latest-only origin/session/protected-work
guard as other links, then selects on the retained `AtlasOrbitModel`, even before its
Rust handle opens. Queue only the latest cold selection; Back before open cancels it.
`selection_id` supports Retry/Back without inventing Thread metadata. Hide the composer
and mutation controls until protected history supplies matching `selected`; a denied
read shows only error/Retry and Back. Preserve drafts across tab changes and reject
incoming links during retained drafts, in-flight writes or create/provider setup.

`AtlasMessagingService` checks the encrypted session, enabled matching registration and
canonical destination origin before rendering any data. Schema v1 optional `title`
(80 codepoints) and `body` (320) are bounded plain text, not actions or HTML. Missing or
invalid text falls back to the generic alert for older servers. Completion context uses
BigTextStyle with PRIVATE visibility and an explicit generic public lock-screen version;
Android's user/channel lock-screen preview controls remain authoritative. The only tap
action is the separately validated destination URL. Never log push content or credentials.

Run root Mise Android build and Kotlin lint tasks. Keep new activities non-exported
unless a deliberately validated deep-link contract is added; MainActivity exports only
the validated OAuth/navigation/App-Link entry points. Do not persist drafts in
saved-instance bundles or backups.
