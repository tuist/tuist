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

Orbit's Photo action uses the platform photo picker (document-image fallback on older
devices); File uses OPEN_DOCUMENT without storage permissions or persisted URI grants.
`MainActivity` forwards only the pending retained model's result. `AtlasOrbitAttachments`
reads `content:` streams off the UI/credential workers, treats provider names/types/sizes
as untrusted, and bounds actual bytes even when metadata is absent or dishonest. One file
is uploaded at a time, up to four per message and 5 MiB per file. Rust owns pending bytes,
stable upload/send retry UUIDs and chips; typing must not replace attachments, and Send
must remain disabled for an unresolved upload. Picker/import work and attachment-only
drafts participate in the existing protected-work guard. No bytes go in saved bundles,
preferences, logs, or notification text.

Opening a message attachment performs a protected Rust download and rechecks the current
thread/foreground epoch before and after private-cache creation. Filenames are display
metadata, never paths. `AtlasOrbitAttachmentProvider` is non-exported and read-only,
exposes only opaque random temporary tokens, and grants only a VIEW read permission.
Remove files/grants on selection changes, revocation, screen close, session end, and
return to the app; files handed to an external viewer expire after five minutes. Do not
clear a valid grant merely because launching that viewer backgrounds Atlas. A viewer
that already consumed bytes is outside Atlas's revocation boundary. Stale downloads or
cache completions must not open another Activity or leave temporary files behind.

Consecutive tool calls are compact expandable presentation groups over unchanged server
messages. Only validated `parent_message_id` links to a loaded root tool permit one
nested child level. Orphan/off-page/cyclic/deeper claims remain visible roots. Keep
children inspectable through the same tool/card/source controls; never infer hierarchy
from tool names or evidence text, nor synthesize NSH payloads from tool output.

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
