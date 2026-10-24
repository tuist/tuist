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
existing draft. `AtlasVoiceInputView` keeps waveform, Cancel and Done accessible.
`AtlasMarkdown` renders bounded agent Markdown with native selectable text; no HTML,
WebView, remote images, custom-scheme links or executable fenced content.

Initial list roots explicitly anchor at the top and use large navigation titles;
do not insert zero-height readiness rows that become the List's first scroll item.
Preserve user scroll positions after navigation and when appending existing lists.

Add new Swift sources to explicit Once source lists where needed, particularly the
unhosted test bundle. Run `once build AtlasIOS`, `once test AtlasIOSTests` and
`once lint AtlasSwiftLint` through Mise with local caching. Tests use Swift Testing
and per-test storage adapters, not global credential/environment mutation.
