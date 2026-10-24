# Atlas iOS

SwiftUI owns presentation; Rust owns OAuth, Orbit session state and allowlisted Automation networking.
Keep shared section strings/routes in the Rust navigation catalog. Do not add a web
view, source interpreter or independent networking/token-refresh implementation.

`AtlasAuthentication` is the MainActor coordinator for credential mutation and shared
in-flight refresh. Persist rotations before requests, fence both successes and errors
by session generation, and discard cancelled/late responses. Blocking Rust calls run
on a GCD background queue, not the UI thread or Swift's cooperative executor. Keychain
contains opaque sessions and unconfirmed launch payloads; never log either.

Automation uses Workflows, Activity and Approvals. Forms bind reviewed revision/input
and stable request IDs; malformed/unsupported schemas must offer web fallback. Required
objects survive omitted optional children; false, zero and absence are different.
Explicit approval confirmation displays the exact persisted payload. Navigate only
after the launch review sheet dismisses. Results are separate protected reads.

Execution subscriptions run only in an active scene. Reconnect from authoritative
state, retain monotonic sequences, fall back to HTTP when WebSockets fail, and clear
inaccessible data after revocation. Backgrounding must not cancel the durable run.
Automation has no Live Activity or background execution/approval notification integration;
the separate native push coordinator supports APNs for other fixed notification kinds.

`AtlasVoiceInput` owns local microphone/Apple Speech lifecycle, required on-device
recognition, permission errors and generation-fenced callbacks. Never fall back to
remote transcription, upload audio or auto-send the accepted text. Cancel on scene
inactivity and thread departure; an unfinished transcript must not replace the
existing draft. `AtlasVoiceInputView` keeps waveform, Cancel and Done accessible. The stable
44pt microphone supports hold-to-record/release-to-review and tap/accessibility
hands-free start/stop. Its native button/long-press recognizer arbitrates taps and
holds without firing both actions on release. Release/cancellation during permission setup
cancels that attempt with explicit retry guidance; never silently switch a held gesture to
hands-free recording after a prompt. A cancelled queued start cannot activate the mic afterward. Neither release nor
stop accepts or sends a draft. Keep both composer actions 44pt and bottom-aligned,
with the send circle drawn inside its target rather than inflated by button style.
Agent activity belongs at the end of the scrollable transcript, not in the composer.
`AtlasThreadMessageView` shows authorized account cards inline; keep raw tool
evidence collapsed until requested through its disclosure header or the card's source action.
`AtlasMarkdown` renders bounded agent Markdown with native selectable text; no HTML,
WebView, remote images, custom-scheme links or executable fenced content.

Initial list roots explicitly anchor at the top and use large navigation titles;
show initial loading as an overlay, not a temporary first row that becomes the List's
scroll anchor. Preserve user scroll positions after navigation and when appending existing lists.
Keep presence inside native navigation toolbars with `AtlasPresenceToolbar`, never
in a changing safe-area inset around the entire TabView. The compact participant
menu must not cover navigation controls or expose stale names on local-only screens.
Tab models retain loaded data for the signed-in session; returning to Orbit reuses
its Rust snapshot, while pull-to-refresh and live invalidations keep it current.
Do not persist authenticated responses to a shared or disk cache to mask layout bugs.

Add new Swift sources to explicit Once source lists where needed, particularly the
unhosted test bundle. Run `once build AtlasIOS`, `once test AtlasIOSTests` and
`once lint AtlasSwiftLint` through Mise with local caching. Tests use Swift Testing
and per-test storage adapters, not global credential/environment mutation.
