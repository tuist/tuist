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

Orbit uses one aggregate ActivityKit Live Activity for the signed-in person's active
work. `AtlasOrbitLiveActivity` reconciles the authorized fixed-route Rust projection
in the foreground and registers per-activity tokens for server APNs updates in the
background. End on sign-out, unavailable access or no remaining work; keep transient
failures visibly stale rather than inventing progress. Suppress recreation of work
the person dismissed. Lead with the authorized bounded conversation title and
secondary phase; titles can appear on the Lock Screen and travel through APNs.
Mark titles privacy-sensitive for system redaction. Never add message excerpts,
people, tool names or results. The data contract and WidgetKit renderer live in
[LiveActivity](LiveActivity/AGENTS.md); the extension has no credentials/networking.

`AtlasVoiceInput` owns local microphone/Apple Speech lifecycle, required on-device
recognition, permission errors and generation-fenced callbacks. Never fall back to
remote transcription, upload audio or auto-send the accepted text. Cancel on scene
inactivity and thread departure; an unfinished transcript must not replace the
existing draft. `AtlasThreadComposer` shares one native Liquid Glass pill on iOS 26+
between text and voice input, with regular Material on older systems and an opaque
system surface for Reduce Transparency/increased contrast. Keep its input/gesture
hierarchy stable when accessibility changes, and let the transcript show through rather
than adding an opaque full-width plate. Utility controls use neutral circular fills.
During dictation, show measured audio levels between a stop microphone and a separate discard control.
Release/tap-stop synchronously adds the current hypothesis as editable text; there is no
review/Done phase or visible live transcript. Only the idle composer's send action sends a message. The stable
44pt microphone supports hold-to-record/release-to-edit and tap/accessibility
hands-free start/stop. Its native button/long-press recognizer arbitrates taps and
holds without firing both actions on release. Release/cancellation during permission setup
cancels that attempt with explicit retry guidance; never silently switch a held gesture to
hands-free recording after a prompt. A cancelled queued start cannot activate the mic afterward. Neither release nor
stop sends a draft, and stale callbacks cannot alter later edits. Keep both composer actions 44pt and bottom-aligned,
with the send circle drawn inside its target rather than inflated by button style.
Agent activity belongs at the end of the scrollable transcript, not in the composer.
`AtlasThreadActivity` uses animated dots for typing and Pip for queued/tool/compaction
work; Reduce Motion keeps both still. Tool labels come only from running server tool
messages while the authoritative agent status is running; idle/reconnecting shows no invented work.
`AtlasThreadMessageView` shows authorized account cards inline; keep raw tool
evidence collapsed until requested through its disclosure header or the card's source action.
`AtlasMarkdown` renders bounded agent Markdown with native selectable text; no HTML,
WebView, remote images, custom-scheme links or executable fenced content.

Orbit's welcome and empty private thread use the bundled `AtlasPipView` mascot and
draft suggestions. Touch duration and tap cadence vary its expressions; never claim
pressure sensing. Reduce Motion preserves expression changes without movement.
Orbit lists authorized private and shared conversations in a native plain inbox with
Today/Yesterday/Earlier sections, title, available summary and private/shared metadata.
Use static localized times/dates, not a ticking relative-time label. Active/Archived is a
native segmented picker; eligible owners get swipe/context Archive and Restore actions.
Confirm shared archive because it makes the conversation read-only for everyone. Archived
details preserve readable history and replace the composer with an owner-only Restore action;
restoring does not ask Pip to resume. Server ownership and status remain authoritative.
Dates accept server microseconds and legacy whole seconds. Navbar compose opens a distinct
private conversation with welcome/suggestions, rather than a fixed bottom Ask bar. Suggestions
append to the existing draft and never send. Notification links select an authorized
thread by UUID through Rust before showing its detail; tab returns must not replay them.
Push settings disclose that completion alerts contain a title and reply preview.

`AtlasThreadMentions` offers bounded eligible-person suggestions for a trailing `@query`.
Only choosing a person records an identity through Rust; typing a name alone grants no
access. Rust retains mentions with per-thread drafts and send retry identities. Sending
the first invitation asks for confirmation that existing messages and attachments become
visible to the invited people. Promotion uses participant-scoped shared access, not
anonymous or company-wide publication. Render `notice_kind: handoff` as a distinct native
conversation-recap card. After promotion render the authoritative selected kind/title,
not the private navigation placeholder, and keep shared threads visible in the list.

`AtlasThreadAttachments` owns native Photos/file import, bounded local reads and
protected QuickLook files. Selection only stages a file; the composer explicitly
sends it, including attachment-only messages. Preserve Rust-owned upload retry IDs,
drafts and failure state. Cancel pending imports/downloads on departure and reject
late results before creating preview files. `AtlasThreadTimeline` nests research
lookups under task cards, preserves off-page children and keeps source disclosures
native; rich tool cards still use the reviewed bundled Native Shell components.
Its prompt index lists loaded human messages with timestamps (and authors in shared
threads), loads earlier history explicitly and scrolls to stable message IDs without
changing drafts or execution state. Dismiss the index sheet before animating its jump;
Reduce Motion jumps without animation. Follow appended and growing content only while
the person is at the bottom, preserving history readers' positions. `AtlasThreadScrollState`
keeps follow intent through lazy layout, activity and keyboard corrections. Native scroll
phases distinguish user scrolling/deceleration on iOS 18+; iOS 17 rebases geometry across
layout changes, tracks genuine drags and accumulates slow movement after corrections settle.
Only follow-intent changes publish view updates, not every offset sample. Bottom settlement
requires proximity to the viewport's bottom edge in both directions; accepting an overscrolled
content bottom can leave every message above the screen. Preserve row-position binding only while
reading history; it must not compete with the bottom anchor. Coalesce bottom requests
after layout and keep correcting until geometry reaches the bottom, including content insets.
Prepare timeline groups once per changed message snapshot, never inside lazy row builders.
Unchanged Markdown avoids reparsing during scroll, presence and draft updates.
Ignore repeated Orbit snapshot sequences and unchanged presence values rather than
invalidating the navigation stack on idle long-poll responses. Theme arrival must change
scroll-container styling without replacing its structural identity.
Show loading feedback before the first protected history
request completes. Approaching the top automatically loads one earlier page, retaining the
current visible message through SwiftUI scroll-position binding, not a forced jump to the
old first row after the response. The timeline's lazy stack owns stable group IDs and the
scroll-target layout; the fixed header/footer stack must not mark the whole timeline as one
target. Keep manual retry and never loop failed requests.
Keep the latest-message action beside the index
and reserve transcript space so these controls do not cover message content.

`AtlasProfile` owns the description editor's state and stale-read fence. Profile
suggests role/personality/preferences when empty and discloses private-thread
provider use. Save only the description, retain failed drafts, and protect active
editors from deep links. It does not change the fixed Pip identity or permissions.

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
