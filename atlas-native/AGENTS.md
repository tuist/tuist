# Atlas native

This is an independent Once workspace for Atlas's native clients. The shared
Rust core owns the hierarchical domain/section catalog and destinations; the CLI is Rust, Android
uses Kotlin with platform widgets, and iOS uses SwiftUI. Native views must not duplicate catalog
strings or routes. Authentication networking and OAuth state live in the independent
Rust `auth/` crate (see `auth/AGENTS.md`); native adapters own browser presentation
and secure persistence. Automation is native (run, monitor, approve) through Browse;
workflow authoring remains web-first. Orbit, tasks, sales accounts, manual invoice bookkeeping, time off,
and Profile are native on both platforms. Mobile navigation hides browser-only
catalog entries and empty ancestor groups. Profile uses authenticated APIs on the
selected server. OAuth tokens are not browser cookies.

## Horizontal architecture and parallel work

- Keep UI features and their state independent: Orbit, Tasks, Accounts, Finance, Time off, and Profile should be understandable and buildable without routing every operation through one screen or global model. The app shell composes destinations; feature models own their drafts, pagination, errors, and mutations. Share code where contracts genuinely match, not through a universal navigation/state framework.
- Apply the same boundaries to Rust business logic and the Once graph. Keep navigation, authentication, fixed-route feature APIs, and CLI responsibilities separate, with explicit dependencies and source lists so independent compilation, tests, and cache reuse can run in parallel. Add feature targets when a real dependency boundary justifies them; do not create wrappers or targets for every file.
- Parallelize independent requests and computation away from the UI thread. Serialize only invariants that require it: OAuth refresh rotation and secure persistence, session replacement/sign-out, and conflicting mutations of the same record. Do not extend the credential queue or a feature's busy flag into a global API lock. Reject stale session results and bound networking concurrency; parallelism must not introduce duplicate writes or refresh-token reuse.
- Keep separately owned changes in disjoint feature files when possible. Native adapters own platform rendering and secure storage; Rust owns transport validation and fixed-route contracts; server contexts own authorization, transactions, and audit rules.

## Layout

- `once.toml`: typed build graph and shared cache identity (`tuist/atlas-mobile`).
- `modules/`: selected Apple SDK linker flags and checksum-pinned NSH SDK imports; see `modules/AGENTS.md`.
- `cards/`: bundled NSH thread result renderer and source/bundle verification; see `cards/AGENTS.md`.
- `core/src/`: dependency-free shared navigation, C ABI, and primitive-only JNI bridge.
- `auth/`: Rust OAuth networking, owned JSON C ABI, and string JNI bridge. Keep it
  independent of navigation/CLI builds. Platform-specific Cargo dependency targets
  expose individual crates to Once for parallel compilation and reusable cache keys.
- `Cargo.toml` / `Cargo.lock`: Rust workspace for editor and Clippy support. Once
  excludes Cargo discovery here to avoid duplicate targets alongside the authored
  graph.
- `cli/`: host Rust executable sharing the catalog; see `cli/AGENTS.md`.
- `core/include/`: authored C header and Clang module map imported by Swift.
- `android/`: Kotlin platform-widget UI, JNI adapter, manifest and resources; see `android/AGENTS.md`.
- `ios/`: SwiftUI app, Swift adapter, Info.plist and Swift Testing bridge/form tests; see `ios/AGENTS.md`.
- `android/distribution/`: stable-key Android signing and publication guard; see
  `android/distribution/AGENTS.md`. PR/debug builds must never supply verified-link identities.
  The signed-out screen matches Tuist's login layout with Atlas's azure palette,
  the shared Tuist mark used by Atlas's web login, and supported hosted/self-hosted actions.
  iOS also offers Sign in with Google using the shared Rust provider hint and the
  same PKCE browser flow, not a Google SDK or a separate token exchange. Keep native browser auth separate
  from presentation; restore sessions automatically rather than exposing a debug
  restore button.
- `ios/distribution/`: post-build ad-hoc device signing and IPA packaging; see
  `ios/distribution/AGENTS.md`. Reuse the Tuist distribution certificate with an
  Atlas-specific profile; device enrollment and 1Password setup are in the README.
- `previews/`: isolated native Settings screenshot harnesses and UI tests; see `previews/AGENTS.md`.
- `resources/`: shared login/launcher-asset generation and packaging checks; see
  `resources/AGENTS.md`. Checked-in backgrounds, marks and launcher icons feed
  the iOS asset catalog and Android resources.
- `mise.toml` / `mise.lock`: pinned Once, Rust, Kotlin and ktlint toolchains.
  ktlint uses an explicit GitHub backend and locked archive, compatible with the
  repository's pinned CI Mise version. Do not rely on a backend name that only
  exists in a newer local Mise registry. The local postinstall hook prevents
  unrelated monorepo CLI bootstrapping.
- `tuist.toml`: Tuist preview and bundle-inspection project configuration.

## Validation

Run commands from this directory, not the monorepo root:

```sh
ONCE_CACHE_PROVIDER=local mise run check
ONCE_CACHE_PROVIDER=local mise run build:cli
ONCE_CACHE_PROVIDER=local mise run test:cli
ONCE_CACHE_PROVIDER=local mise run build:android
ONCE_CACHE_PROVIDER=local mise run build:ios
ONCE_CACHE_PROVIDER=local mise run test:ios
mise run lint:rust
ONCE_CACHE_PROVIDER=local mise run lint:swift
mise run lint:kotlin
```

Install the Rust standard library for the platform before building:
`mise exec -- rustup target add aarch64-linux-android aarch64-apple-ios-sim`.
Android needs `ANDROID_HOME`, SDK 35, build-tools 35.0.0 and an NDK selected by
`ANDROID_NDK_HOME` (CI pins 27.3.13750724). CI initializes command-line SDK tools
with `setup-android`, explicitly requesting `platform-tools` rather than its
retired default `tools` package, and generates an ephemeral debug keystore for
Once's required APK signing. Local setups need `ANDROID_DEBUG_KEYSTORE` or
`~/.android/debug.keystore`; see the README for key generation. iOS needs Apple
Silicon macOS, Xcode, and an installed iOS simulator runtime. Do not switch this workspace to Gradle,
SwiftPM, or generated Xcode projects to work around Once build failures.

## Native Automation

The shared auth crate allowlists authenticated JSON requests and bounded Phoenix
WebSocket subscriptions; navigation core stays dependency-free. The server owns
contract validation, revision checks, authorization, durable progress and approvals.
Native controls project supported schemas and explicitly fall back to web for
unsupported shapes. Do not execute workflow source on a phone or render server HTML.

A reviewed launch freezes revision, inputs and a UUID request ID. Securely retain an
unconfirmed request and replay it unchanged; never turn a timeout into a new request.
Pending requests belong to the credential lifetime and are cleared on explicit new
sign-in/sign-out. Execution watches are foreground-only, reconcile on reconnect and
HTTP fallback, and report real phases/steps/waits rather than percentage progress.
Approval confirmation shows the persisted payload and binds its digest to the decision.
Protected results are fetched separately, never carried on progress channels.

Automation has no ActivityKit/WidgetKit extension or background execution/approval
notification integration. Once 0.68.2 has no Apple extension target. The separate
native push subsystem below supports other fixed notification kinds; do not imply
that it delivers Automation progress or decisions. Do not keep Automation sockets
alive in suspended apps or claim real-device activity validation.
## Workspace navigation

- The signed-in shell has five stable destinations: Orbit, Accounts, Finance, Browse, and Profile. Orbit is the feature, with stable navigation ID `orbit`; Thread is the persistent entity. Keep `orbit_session`, `/api/native/orbit/threads`, `orbit:thread:<uuid>` and `orbit:me` aligned with the server, with explicit private/shared thread terminology. Tasks remains a native Browse shortcut; existing task links open Browse → Tasks, including direct record reads. iOS uses a native TabView, sidebar-adaptable on iPad/iOS 18+, without automatic More overflow. Android uses platform widgets with readable 48dp+ destination controls and larger-text wrapping. Browse is a searchable hierarchical directory of implemented native screens only. Add future domains there rather than expanding the tab bar indefinitely. Unavailable permissions show an explanation inside a stable tab, not a disappearing destination.
- `core/src/navigation.rs` owns stable IDs, titles, descriptions, parent groups, canonical URLs, native screen keys, shortcut placement, and required browser scopes. Root domains mirror Atlas: Automation, Overview, Commercial, Outbound, Engineering, People, Operations, Library, and Admin. Automation uses its own native feature views through Browse without adding a sixth top-level tab; retain the original five section indices and the expanded eight-field bridge. Commercial contains Sales, Finance, and GTM; Operations contains Hardware. The catalog includes the existing domain entry points, including customer evaluations, vendor costs, postal correspondence, engineering specs, hardware financing/insurance, documents, and administrative tools. Add future destinations/groups here rather than hard-coding new menus in either platform.
- C/JNI section fields 0–3 and the original five indices remain compatible. Fields 4–7 expose stable ID, group ID, shortcut flag, and required web scope. The parallel group bridge exposes title, description, stable ID, parent ID, and placement. Group strings have the same immutable process-lifetime ownership and primitive JNI rules as section strings. Rust tests enforce unique routes/IDs, reachable nonempty groups, valid parents, acyclicity, and stable original destinations.
- iOS `AtlasWorkspaceView` composes native NavigationStack/List destinations. Android `AtlasWorkspaceModel` owns the selected group and search without retaining an Activity; `AtlasWorkspaceScreen` owns SearchView and directory rows, and `AtlasHomeScreen` composes the stable destinations. Retain models across configuration changes, save only validated navigation IDs for process restoration, disable automatic form/search state persistence, and detach old listeners. Back clears search before ascending the hierarchy, with system Back/Up support; drafts survive rotation and failed saves.
- The shared catalog/CLI retain web routes, but mobile never displays browser-only entries. Scope metadata is descriptive, never a local authorization grant; Atlas enforces actual access. Implement future native adapters under the same stable destination IDs without changing the information architecture.
- Coverage includes the Rust graph/ABI tests, `ios/Tests/AtlasCoreTests.swift`, and fixture-backed `AtlasWorkspaceUITests` / Android workspace model checks and `capture_android.py --workspace`. Keep fixtures outside production source globs; see `previews/AGENTS.md`.

## Object navigation and deep links

- See [Object navigation](README.md#object-navigation) for the link contract, notification payload and agent automation commands. `core/src/destinations.rs` owns the linkable screen allowlist and record capabilities, exposed through a separate immutable C/primitive JNI descriptor table. Keep existing section/group fields unchanged. Screen keys are public, frozen route identifiers; titles and catalog placement can evolve independently.
- `dev.tuist.atlas://navigate/<screen>[/<uuid>]?server=<encoded-https-origin>` is an untrusted, read-only intent, never an API path or server switch. Native adapters validate the exact grammar and compare the authenticated HTTPS origin (host case/default 443/root slash normalized, nondefault ports distinct). OAuth callbacks remain separate. The server still authorizes every direct record read.
- HTTPS Universal/App Links for the hosted domain enter the same destination contract. C/JNI destination fields 2–3 expose existing browser pages and accepted record prefixes. Canonical share URLs use `/open/<screen>[/<uuid>]`; registrations claim only the exact equivalent web pages and these landing paths, never entire web hierarchies. The broader finance dashboard is explicit-open only. Keep the Android manifest in sync with `AtlasWeb.NativeLinks.claimed_paths/0`; only the native parser validates lowercase UUIDs. Do not forward query/fragment data, trust Host headers, or infer server changes from links. See `atlas/deploy/AGENTS.md#native-app-links` for trusted identities and rollout.
- Native browser escape uses embedded Safari on iOS and explicit browser components on Android to avoid immediately handing a verified URL back to Atlas. Keep browser auth separate from native OAuth; browser presentation must not erase native drafts. Dismiss embedded Safari on a new handled link or link error.
- The shell owns only a latest-wins, memory-only pending destination and native parent stack. Retain Android pending state across rotation, never replay Recents intents, and discard on session end. Do not persist destinations across users or put credentials in URLs. Reject links during drafts/saves/AI setup with an explanation rather than discarding work or silently navigating after save. Features still own state and fetch records by UUID, not by searching loaded pages; loading/failure states must never expose mutation controls. A forbidden direct-record read must revoke cached rows/options and invalidate older list/detail reads so late responses cannot restore them, while cancelled requests must not revoke newer results. Keep Back and explicit Retry available.
- `AtlasNavigationTests`, `AtlasBusinessTests`, Rust capability/ABI tests and Android preview startup checks cover grammar/lifecycle/direct lookup, including revoked-access cache invalidation and late/cancelled reads. `AtlasNavigationUITests` exercises the production iOS destination views using isolated fixture data. Keep all fixture URL launch arguments outside production source globs.

## Native business records and Profile

- People is a native Browse destination. The shared Rust auth crate owns the persistent Phoenix WSS connection, location validation, heartbeats/reconnect and latest-only event delivery; Swift/Kotlin models only bridge events and app lifecycle. Foreground clients report the current allowlisted page/record, clear stale same-page hints on navigation, and close on background/sign-out. Refresh/persist OAuth credentials through the existing coordinator before opening, never serialize blocking event waits with credential or business work. Presence describes viewing, not editing, and grants no write permissions. Server coordination and privacy rules live in [Atlas presence](../atlas/lib/atlas/presence/AGENTS.md).
- `auth/src/business.rs` allowlists resources, actions, fields, IDs and dates for `/api/native/tasks`, `/api/native/accounts`, `/api/native/invoices`, and read-only `/api/native/profile`. See the [server contract](../atlas/lib/atlas_web/controllers/AGENTS.md). Missing optional record values are empty strings; mutation attributes are strings, with empty strings clearing optional fields. Task completion is a dedicated action, never an editable status.
- `AtlasBusiness` / `AtlasBusinessModel` accumulate list pages as users scroll. Preserve rows and scroll position on append, deduplicate IDs, stop automatic retries after a failed next page, and reset pagination on search/filter/refresh. iOS preserves the native List on initial arrival and page append. Reset its identity when search/filter criteria change or a loaded later page returns to page 1; programmatic section scrolling can collapse the large title and clip headers under navigation. New criteria supersede in-flight reads; late results must never restore old rows or errors. Preserve a successful mutation when the following refresh fails, prevent double submission, confirm deletions/discards, and retain drafts on failure. Use native date/time controls, locale-safe amounts, and server-provided enum/relationship options.
- Business filters use native menus/pickers on iOS and toolbar menus/selection dialogs on Android. Apply filters on the server before count/pagination, never just to the loaded page. Task grouping consumes `fields.reminder_group` with server-wide overdue/upcoming/none/completed ordering; overdue means an open task with an expired `remind_at`, not a past `due_on`. Display active filters and a reset action. Keep invoice summaries unfiltered.
- Account rows/detail reuse the web app's Google S2 domain favicon endpoint with URL-encoded `primary_domain`, decorative rounded images and initials fallback. Image requests are credential-free and independent of Atlas OAuth transport; missing/failed logos must not block the list. Android image work is bounded and detached when rows leave the screen.
- iOS account details use `AtlasAccountDetailSections` for grouped overview, billing/address and collapsible related records with read-only drilldowns. Contract values come from the server's derived term value, not a potentially stale scalar. Load details on entry/refresh and after closing the editor; list refresh must not discard already loaded details. Older servers retain the basic field view. Document summaries are server-filtered by `documents:read`; no native download or storage URL is introduced.
- Finance is read-only bank overview plus manual invoice bookkeeping, not bank administration or payments. Imported/linked invoices are read-only even for finance writers. iOS `AtlasFinanceOverviewView` uses the server's optional unfiltered `finance_overview` for cash, burn, runway and six months of income/expenses in one reporting currency. Preserve it across appended invoice pages and replace it on refresh. Show no-account, missing-FX and older-server explanations rather than zero/partial totals. Swift Charts has distinct income/expense series and exact textual monthly values. Android's legacy chart still uses original-currency invoice `summary`; do not relabel invoice totals as cashflow or balances.
- Profile follows Tuist iOS's grouped identity/email/version/sign-out layout, adding the selected server URL, authenticated server version, and existing Claude/ChatGPT settings. Display the server-reported application version, never a protocol constant or invented revision. Profile does not grant identity or server configuration writes.

## Native push notifications

- Push is opt-in from Profile, separate from presence. The server advertises configured platforms through optional `push_notifications` in Profile. Older servers remain usable. Lock-screen content stays generic; tap URLs re-enter the existing origin-bound destination parser and still require server authorization.
- The shared `auth/src/push.rs` owns fixed bearer registration routes. Swift `AtlasPushNotifications` and Kotlin `AtlasPushNotifications` own platform consent/token callbacks and serialized registration/cleanup. Installation IDs and cleanup markers use the existing device-only secure stores. Mark a registration disabled before discarding an authenticated session; a new user never inherits opt-in. Retry offline cleanup on the same origin using that installation's native OAuth client. Encrypted registration and cleanup records are keyed by canonical server origin, so another server's pending cleanup neither inherits opt-in nor blocks enrollment. Rejected startup sessions must disable the saved session's origin even before the push coordinator is configured. Deleted IDs are terminal and must be replaced.
- iOS uses the application and notification-center delegates, registers with APNs on launch/foreground, and passes cold-start taps through AtlasNavigation. A queued generic alert can still be displayed by iOS after logout because the app cannot retract an already accepted provider alert. Signing derives the environment from the provisioning profile; see `ios/distribution/AGENTS.md`.
- Android uses the official Firebase SDK, explicit Application initialization and data-only messages. The service never authenticates or registers devices: it drops messages unless a current encrypted session and enabled server registration match the payload. Runtime notification permission, a notification channel, and Google Play services are required. No Firebase identifiers means disabled push, not broken authentication. Public project identifiers can be imported with `python3 android/push/configure.py /path/to/google-services.json`; never use a service-account JSON in the app. See [Android push packaging](android/push/AGENTS.md) for the lock, manifest audit and final-APK resource gate.
- No production credentials, cloud resources or provider configuration are provisioned by builds. Physical-device foreground/background/terminated delivery and account-switch smoke tests remain required before enabling production notifications.

## Server-controlled appearance

- `auth/src/themes.rs` owns optional credential-free catalog fetch/validation under `/api/native/themes`, plus bundled Atlas defaults. Unsupported/invalid/unreachable catalogs must never affect OAuth state or block the workspace. Newer clients work with older servers, including their authenticated dynamic route returning 401. See [the versioned server contract](../atlas/lib/atlas_web/controllers/AGENTS.md). Keep all three production Rust Once source lists aligned.
- Swift `AtlasAppearance` and Kotlin `AtlasAppearance` cache only validated catalogs and theme/appearance preferences per canonical selected server origin, using a worker independent of the credential coordinator. Refresh on foreground with a five-minute minimum interval; reject late results after server changes. Retain an unavailable theme ID but render the current server default, then bundled Atlas. Sign-out restores unthemed login. Profile → Appearance selects Server default or a published theme and System/Light/Dark locally, never a server-side user setting.
- Appearance is local-only: clear Profile's viewing location on entry, just as AI-account child screens do. Location-free presence must not report a same-page hint or place a banner over native navigation. A Profile link returns from Appearance to the Profile root without resetting the selected theme or appearance preferences.
- Preserve platform controls, hierarchy, semantic status colors, Dynamic Type/font scaling, 44pt/48dp targets and native navigation. iOS keeps system row surfaces/labels/chrome; custom canvas/tint and app-owned preview/action styling follow HIG color and accessibility guidance. Increased contrast drops custom iOS styling. Server tokens cannot download fonts, inject CSS, resize native controls or replace navigation. Avoid a universal screen/state framework for theming.

## Orbit (threads)

- The first tab renders the instance's private companion thread and shared agentic threads. Pip is the fixed assistant/mascot, not a configurable persona. The server returns this identity and whether an Orbit inference profile is configured; no hosted provider, person, or upstream tool is assumed. Older servers show an in-tab explanation instead of blocking the workspace.
- `auth/src/orbit_session.rs` owns feature state and orchestration: pagination, chronological history reconciliation, per-thread drafts and retry IDs, stale-selection fences, access-loss invalidation, and foreground live connections. Its opaque in-memory handle exposes monotonically sequenced snapshots. `orbit.rs` owns the typed fixed-route HTTP contract; `orbit_live.rs` owns authenticated Phoenix framing and bounded latest-only invalidations. Persisted history and deployment recovery belong to the Atlas server, not to these mobile handles.
- Swift `AtlasOrbit` and Kotlin `AtlasOrbitModel` are thin snapshot adapters. Keep business decisions in Rust. Native code owns presentation, UI text bindings, scroll position, tool-card expansion, platform lifecycle, and refreshing/persisting OAuth credentials before authenticated commands. Never put a blocking `next` wait on the credential queue or UI thread. Close handles on sign-out, stop live viewing in the background, and ignore older snapshot sequences.
- Thread details hide the tab bar and keep a keyboard-safe composer at the bottom. Message bubbles distinguish the current person using the server's presence `self_id`, not names or thread ownership; unknown identity stays incoming. Summary, origin, status and participants remain in the thread details sheet rather than competing with messages. Preserve Dynamic Type, theme contrast, selectable text and access to expandable tool evidence.
- The Atlas server is the source of truth for thread content, run state and cards. It supplies an optional versioned component with bounded data, permitted actions and text fallback. Rust validates that contract but never synthesizes cards from tool output. The bundled NSH renderer displays `result_table` and `account_card` v1 inside expandable tool evidence; Swift/Kotlin only host it. No remote code/package loading, network credentials or autonomous client execution is permitted. See [card boundaries](cards/AGENTS.md). API 26–27 Android and unsupported/failed renderers retain text.
- Tool calls render as expandable evidence, not raw executable UI. Shared replies explicitly choose whether to ask the agent; private messages always address it. Server authorization governs membership, leadership-sensitive history, and tool access. Clients never infer authority from a participant label or locally available tool names.
- Preserve the authorized server `agent_status` from both HTTP and Phoenix snapshots, including changes without a message revision. iOS presents queued/running/compacting status; reconnecting is separate from agent work and unknown/idle states show no invented activity. Condukt owns compaction, not the native session.
- iOS voice input uses Apple Speech's required on-device recognition, never a cloud fallback or audio upload. Cancel/background/navigation discard unaccepted audio/transcripts without changing the Rust draft; Done appends editable text and never sends it. `AtlasMarkdown` renders bounded agent Markdown natively without HTML, remote images or executable content.
- Swift adapter tests live in `ios/Tests/AtlasOrbitTests.swift`; shared transport/state tests live in `auth/src/orbit*_tests.rs`. The isolated iOS workspace preview renders fixture-only thread snapshots; it makes no model requests and does not prove deploy recovery or live collaboration.

## AI account settings

- iOS opens native AI settings from Profile using SwiftUI Form, NavigationLink, SecureField, and confirmation dialogs. Android uses the platform Toolbar, wrapping two-line list rows, a dedicated secure-token screen, and AlertDialog for destructive confirmation. Mobile apps exclude catalog settings destinations from Browse; the shared catalog/CLI keep the existing `/settings/llm-providers` web destination.
- `ios/Sources/AtlasAIAccounts.swift` owns the iOS account state; `AtlasAIAccountViews.swift` owns provider setup and `AtlasProfileView.swift` owns Profile presentation. The auth coordinator caches one model per signed-in session, using a weak, session-identity-checked request closure; leaving Settings must not discard failed cancellation handles. Keep native settings rows icon-led with secondary status, setup screens focused on one task with a prominent bottom action, and detailed Claude instructions in a disclosure rather than paragraph-heavy form rows. Preserve Dynamic Type, dark appearance, secure entry, and explicit device-code expiry/cancellation. `android/src/dev/tuist/atlas/AtlasAIAccountsScreen.kt` owns Android presentation; `AtlasAIAccountsModel.kt` owns metadata, requests, and polling without retaining an Activity, View, or token. Retain that model alongside authentication for the signed-in session, including across Settings closure and configuration changes, detach the old view listener without cancelling sign-in, and save only the known Atlas login ID for process-death cancellation. Never save token fields or device codes in view state. All authenticated requests go through the existing auth coordinator and the fixed-route Rust `auth/src/accounts.rs` bridge, never directly from views or via browser cookies. Persist rotated Atlas OAuth credentials before API calls; serialize refresh and sign-out. Provider credentials stay encrypted on Atlas, not in native preferences or model tool arguments. Clear Claude input on submit/dismiss and disable Android form-state saving/autofill.
- Native setup supports Claude create/update, ChatGPT start/poll/cancel, and confirmed disconnect. Poll no faster than the returned interval, stop on completion/expiry, ignore stale results, and cancel on leaving the ChatGPT page, including an in-flight start. Cancellation preserves existing credentials. Reload metadata after cancellation, including an already-completed/expired response, because authorization may have won the race. Retain failed cancellation handles for retry, treat `login_failed` and rejected Atlas refresh credentials as terminal, scope stale errors to their originating page, and never let a late save close a newer form. Android requires cancelling pending sign-in before disconnecting its saved ChatGPT connection. Real-account ChatGPT sign-in still needs an authorized Atlas client. User-triggered agent execution remains separate follow-up work.
- Preserve platform behavior: 44pt iOS / 48dp Android touch targets, accessible labels/headings, system appearance and text scaling, scrollable keyboard-safe forms, and Android system/cutout/IME insets. Use API 33+ Back callbacks with the older Back fallback. Keep API-26 navigation bars dark; dark navigation icons on a light background belong in `values-v27`. Do not add navigation/state frameworks just for these two setup screens.
- Reproducible fixture-backed screenshots and the iOS UI test use separate [preview targets](previews/AGENTS.md). These render production views without authenticating or making account-management requests. Never ship preview fixture sources or authentication bypasses in production apps. Clearly label screenshot evidence as preview-backed.

## Employee time off

- The shared catalog owns the Time off title, description, browser fallback URL, and native screen key. C/JNI field 3 exposes that screen key without changing fields 0–2. Mobile dispatches `time-off` natively instead of opening a browser; the CLI keeps the web destination.
- iOS uses `AtlasTimeOff` with `AtlasTimeOffView`; Android uses the activity-independent `AtlasTimeOffModel` and platform-widget `AtlasTimeOffScreen`. Employees can request inclusive full days, view paginated personal history and Berlin public holidays, edit non-cancelled requests, and confirm cancellation of active requests. There are no mobile approval controls or location selectors. All transitions are enforced by the existing server context.
- Requests use the fixed-route Rust `time_off` auth command and the owner-scoped bearer-authenticated `/api/me/time-off` endpoints, never browser cookies, arbitrary paths, owner IDs, or approval/status parameters. Preserve ISO calendar dates, not UTC instants. Refresh rotation/persistence is serialized by the existing auth coordinator; holiday networking runs outside that credential queue. Session identity checks reject responses from a signed-out/replaced session. Drafts/history remain memory-only; Android retains its model across configuration changes and detaches old view listeners.
- Preserve drafts and loaded history on failures, prevent double submission, and distinguish a failed save from a successful mutation whose subsequent reload failed. iOS uses item-backed editor presentation to preselect the correct request. Android uses native date dialogs and saves its draft in the retained model, not a View. Cancellation and Back must not discard an in-flight save.
- Coverage: Rust `auth/src/time_off_tests.rs`, Swift `ios/Tests/AtlasTimeOffTests.swift`, and server `atlas/test/atlas_web/controllers/time_off_controller_test.exs`. Once's production auth source lists must include `time_off.rs`; test sources remain separate.

## Boundaries

- Navigation C strings are immutable, process-lifetime pointers. Never free them
  in Swift. Authentication responses are separately owned allocations: release each
  exactly once with `atlas_auth_free` and never log requests/results.
- Navigation JNI exports accept only integer values and opaque pointers; they never
  dereference JNI pointers. Authentication uses the `jni` crate for VM string ownership.
  Keep UTF-8 decoding and boundary checks covered by tests.
- Rust auth calls are synchronous and bounded; invoke them from a background executor,
  never the UI thread. Serialize session changes/refresh rotation in native coordinators,
  and persist rotations before requests. Account-management calls currently share
  that coordinator's serial queue with sign-out. Android's auth `busy` flag is for
  session commands, not background account requests, which have their own model
  loading state; never drop sign-out because cancellation was queued. Clear rejected
  sessions/registrations and return to sign-in. Cache the account model only for the
  current signed-in session. Do not extend that queue into a global lock for
  unrelated future networking.
- iOS uses ThisDeviceOnly Keychain entries and a simulator-specific Keychain entitlement;
  device builds must derive their entitlement from the actual signing team/profile.
  The Swift Testing XCTest agent is unhosted and cannot access app Keychain; test
  storage request/failure semantics with a per-test adapter, not mutable global stubs.
  Android uses AES-GCM with Android Keystore
  keys and backup-disabled encrypted preferences. Native code must successfully persist
  credentials before publishing signed-in state. Retain credentials on transient refresh
  failures, and discard rejected registrations so the next login can register again.
- `mise run prepare:rust` materializes locked third-party sources in ignored `.once/vendor`.
  Build/test tasks depend on it; run it before invoking Once directly on a clean checkout.
  Run vendor preparation serially, not concurrently with builds that read that directory.
  Vendoring uses HTTP/1.1 to avoid repeated crates.io HTTP/2 framing failures on macOS runners.
  Once 0.68.2 does not yet include the source-materialization fix in tuist/once#390;
  keep this required workaround until a published Once version includes that fix.
  The Android task exposes API-26 NDK clang and LLVM tools to Cargo build scripts through
  declared `build_script_tools`, so their contents participate in cache identity.
- The Android package, Kotlin class/method names and JNI exported symbols must
  agree. Renaming any of these requires rebuilding and launching the Android app.
- Swift's generated module caches embed absolute paths. After a directory rename,
  discard `.once/out/AtlasIOS/ModuleCache` and the equivalent test target cache
  before rebuilding; do not move those precompiled caches between roots.
- `Info.plist` is a complete template, not a merge into Once's default plist.
  Keep its identifier, executable, families and supported platform consistent
  with the manifest, and smoke-test simulator installation after changes.
- Mobile builds are arm64 Android debug APKs, arm64 iOS simulator apps and arm64
  iOS device apps. `AtlasIOSDevice` uses separate device Rust targets and shared
  production Swift sources; do not ship screenshot fixtures. CI Android and iOS device builds use
  only the local cache, not the shared cache accessible to PRs. Main-branch delivery
  provisions/re-signs a copy as an ad-hoc IPA outside Once's cache. Store delivery
  still requires store setup.
  The CLI builds for the host and is distributed as an executable tar archive;
  it must not be sent to Tuist's mobile preview endpoints.
- GitHub CI uses the existing private Once project. Its repository connection to
  `tuist/tuist` is required for OIDC authorization. Do not put project tokens,
  production signing credentials, or service account credentials in source or
  cached actions. Android debug signing uses the standard public `android`
  password; never commit or upload the generated keystore.
- The single `.github/workflows/atlas-mobile.yml` pipeline triggers automatically
  only for `atlas-native/**` changes and skips draft PRs. Keep building, testing
  and each language's linting in distinct jobs. There is no unconditional merge
  queue trigger because it cannot apply GitHub path filters.
- Main-branch delivery uses the `nightly` Tuist preview track for APK, simulator
  app and signed device IPA, gated by all build, test and lint jobs. Only the
  protected publication job's signing step receives 1Password access; upload
  steps do not. Publish Android (when configured) and the simulator before device
  signing, so a missing Associated Domains profile does not block those builds.
  Simulator uploads set `TUIST_PREVIEW_BUILD_VERSION` to a fresh Unix timestamp, avoiding duplicate
  previews without modifying the bundle or Once's cache. Device packaging already
  stamps its temporary copy before distribution signing. Credential-free packaging
  tests gate publication alongside the build, test and lint jobs. Forks use local caching
  and no OIDC; no PR publishes previews or receives distribution credentials.
