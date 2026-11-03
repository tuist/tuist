# Atlas macOS

The native macOS app compiles the same `ios/Sources` SwiftUI features and Rust
contracts as iOS. `Sources/AtlasDesktopWorkspace.swift` owns only the persistent
desktop sidebar and session-lifetime feature models. Keep forms, API state,
authorization and destination parsing shared. Do not add a web wrapper or fork
business logic. macOS uses one workspace window so presence and session lifecycle
remain unambiguous; Settings is a separate native scene.
The shell retains feature model references without observing their snapshots or
drafts; each feature view observes its own model. Keep Orbit's window title and
toolbar on its stable container so changing conversations does not recreate native
toolbar buttons. Retain the detail, scroll view and composer across selection
changes; scope the transcript and environment activity identity to the conversation
ID and reset presentation state. Loading feedback must not replace the scroll view.
Render history only when the Rust snapshot's selected ID matches the detail,
never the previous conversation's messages under a newly selected title.

Settings uses native General, AI accounts, This Mac and Updates tabs. This Mac is
an owner-private tool environment, never the model/session host. Keep opt-in off
by default, persist disabled consent before enrollment, and scope device-only
Keychain configuration to origin and owner. Use the fixed-route Rust environment
bridge and authenticated Phoenix channel; claim each command once and retry only
its identical result. Revalidate the claimed payload against the displayed command.
File tools enforce descriptor-level project containment; terminal commands
run unsandboxed as the macOS user once terminal access is explicitly enabled,
without per-command prompts. Keep the listener independent of
execution, enforce the 30-minute process-group watchdog, retain only bounded tail
output, and poll claim-bound progress for remote cancellation. Retry identical
results through transient server outages, never commands. Display sharing remains disabled. Never request OS
permissions or enable a real environment from screenshot fixtures. The server owns
durable Orbit runs/checkpoints, frozen environment selection, encrypted command
records, private history and unknown-outcome handling across deployments.

Parent-directory discovery lists immediate non-symlink Git roots. Coding projects
advertise an optional boolean and canonical public-GitHub `owner/repo` identity
from local `remote.origin.url`, never raw remotes, credentials or local paths.
Read metadata off the main actor without fetching; non-GitHub/unrecognized remotes
remain ordinary selectable projects. Repository discovery grants no consent.
With terminal consent,
`read`/`bash`/`edit`/`write` run in a retained worktree scoped by origin, owner,
installation, project and thread. Create it lazily after claim from local HEAD,
never copying dirty files or fetching/resetting/stashing the original checkout.
Use a title slug plus UUID for the initial branch; do not rename a branch the
person may already be using. Descriptor-relative file mutations reject symlinks
and apply unique nonoverlapping replacements atomically against original text,
preserving UTF-8 BOM, newline style and existing permissions. Archive/sign-out
must not delete code; local retention/export is separate from server records.

Build with `ONCE_CACHE_PROVIDER=local mise run build:macos`, test shared adapters
with `mise run test:macos`, and lint through `mise run lint:swift`. The minimum is
macOS 14; gate newer SwiftUI APIs for both iOS and macOS. Native app menus, keyboard
navigation, resizable split views, sheets, semantic colors and selectable text
take precedence over phone-specific chrome. Business collections use native
compact, selectable, sortable tables, not stretched phone rows. Sorting applies
only to loaded rows; preserve server filtering/pagination and currency separation.
Open table records with double-click, Command-O, Return or the context menu. The bottom bar
shows counts/loading/errors, not permanent Open or Load more buttons; visible
trailing rows trigger pagination and a failed page requires explicit Retry.
Orbit follows Mail/Notes: a resizable inset inbox beside the selected conversation,
with native persistent selection and arrow-key navigation, not a full-width push
list. Keep title/date and secondary audience/summary in each row, and Active/Archived
in the window toolbar. Drafts, uploads and voice capture block conversation changes
through the existing protected-work guard; do not discard work when selecting a row.
Orbit displays its private/shared audience in the native window toolbar subtitle,
outside the scrolling transcript, so following the latest message cannot clip it.

APNs uses the shared push coordinator with the AppKit application delegate,
shared iOS/macOS topic `dev.tuist.atlas`, distinct `macos` platform and explicit
server capability. Profile consent, token rotation, origin-bound navigation and
logout cleanup follow the same contract as
iOS. Notification actions reopen the workspace before routing. Only signed
Developer ID delivery copies receive profile-authorized macOS push entitlements
and an environment stamp; ordinary local builds remain unconfigured. Live
Activities remain iOS-only. See the distribution guidance for provisioning and
the Atlas deployment guidance for the separate backend opt-in.

Sparkle is a macOS-only dependency imported by `modules/sparkle.star`; the app owns
one updater for its lifetime. Distribution signing/notarization happens on a copy
outside Once's cached build. Never access release credentials in PR builds or
ship fixture sources. `previews/macos` is isolated offline evidence, not live OAuth
or production update delivery proof.

See [distribution guidance](distribution/AGENTS.md) for the bundle layout,
framework sealing, credential-free signing checks and protected release workflow.
