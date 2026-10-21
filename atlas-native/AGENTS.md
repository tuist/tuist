# Atlas native

This is an independent Once workspace for Atlas's native clients. The shared
Rust core owns the hierarchical domain/section catalog and destinations; the CLI is Rust, Android
uses Kotlin with platform widgets, and iOS uses SwiftUI. Native views must not duplicate catalog
strings or routes. Authentication networking and OAuth state live in the independent
Rust `auth/` crate (see `auth/AGENTS.md`); native adapters own browser presentation
and secure persistence. Tasks, sales accounts, manual invoice bookkeeping, time off,
and Profile are native on both platforms. Mobile navigation hides browser-only
catalog entries and empty ancestor groups. Profile uses authenticated APIs on the
selected server. OAuth tokens are not browser cookies.

## Horizontal architecture and parallel work

- Keep UI features and their state independent: Tasks, Accounts, Finance, Time off, and Profile should be understandable and buildable without routing every operation through one screen or global model. The app shell composes destinations; feature models own their drafts, pagination, errors, and mutations. Share code where contracts genuinely match, not through a universal navigation/state framework.
- Apply the same boundaries to Rust business logic and the Once graph. Keep navigation, authentication, fixed-route feature APIs, and CLI responsibilities separate, with explicit dependencies and source lists so independent compilation, tests, and cache reuse can run in parallel. Add feature targets when a real dependency boundary justifies them; do not create wrappers or targets for every file.
- Parallelize independent requests and computation away from the UI thread. Serialize only invariants that require it: OAuth refresh rotation and secure persistence, session replacement/sign-out, and conflicting mutations of the same record. Do not extend the credential queue or a feature's busy flag into a global API lock. Reject stale session results and bound networking concurrency; parallelism must not introduce duplicate writes or refresh-token reuse.
- Keep separately owned changes in disjoint feature files when possible. Native adapters own platform rendering and secure storage; Rust owns transport validation and fixed-route contracts; server contexts own authorization, transactions, and audit rules.

## Layout

- `once.toml`: typed build graph and shared cache identity (`tuist/atlas-mobile`).
- `modules/`: selected Apple SDK linker flags and binary SDK verification; see `modules/AGENTS.md`.
- `core/src/`: dependency-free shared navigation, C ABI, and primitive-only JNI bridge.
- `auth/`: Rust OAuth networking, owned JSON C ABI, and string JNI bridge. Keep it
  independent of navigation/CLI builds. Platform-specific Cargo dependency targets
  expose individual crates to Once for parallel compilation and reusable cache keys.
- `Cargo.toml` / `Cargo.lock`: Rust workspace for editor and Clippy support. Once
  excludes Cargo discovery here to avoid duplicate targets alongside the authored
  graph.
- `cli/`: host Rust executable sharing the catalog; see `cli/AGENTS.md`.
- `core/include/`: authored C header and Clang module map imported by Swift.
- `android/`: Kotlin UI, JNI adapter, Android manifest and resources.
- `ios/`: SwiftUI app, Swift adapter, Info.plist and Swift Testing bridge tests.
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

## Workspace navigation

- The signed-in shell has five stable destinations: Tasks, Accounts, Finance, Browse, and Profile. iOS uses a native TabView, sidebar-adaptable on iPad/iOS 18+, without automatic More overflow. Android uses platform widgets with readable 48dp+ destination controls and larger-text wrapping. Browse is a searchable hierarchical directory of implemented native screens only. Add future domains there rather than expanding the tab bar indefinitely. Unavailable permissions show an explanation inside a stable tab, not a disappearing destination.
- `core/src/navigation.rs` owns stable IDs, titles, descriptions, parent groups, canonical URLs, native screen keys, shortcut placement, and required browser scopes. Root domains mirror Atlas: Overview, Commercial, Outbound, Engineering, People, Operations, Library, and Admin. Commercial contains Sales, Finance, and GTM; Operations contains Hardware. The catalog includes the existing domain entry points, including customer evaluations, vendor costs, postal correspondence, engineering specs, hardware financing/insurance, documents, and administrative tools. Add future destinations/groups here rather than hard-coding new menus in either platform.
- C/JNI section fields 0–3 and the original five indices remain compatible. Fields 4–7 expose stable ID, group ID, shortcut flag, and required web scope. The parallel group bridge exposes title, description, stable ID, parent ID, and placement. Group strings have the same immutable process-lifetime ownership and primitive JNI rules as section strings. Rust tests enforce unique routes/IDs, reachable nonempty groups, valid parents, acyclicity, and stable original destinations.
- iOS `AtlasWorkspaceView` composes native NavigationStack/List destinations. Android `AtlasWorkspaceModel` owns the selected group and search without retaining an Activity; `AtlasWorkspaceScreen` owns SearchView and directory rows, and `AtlasHomeScreen` composes the stable destinations. Retain models across configuration changes, save only validated navigation IDs for process restoration, disable automatic form/search state persistence, and detach old listeners. Back clears search before ascending the hierarchy, with system Back/Up support; drafts survive rotation and failed saves.
- The shared catalog/CLI retain web routes, but mobile never displays browser-only entries. Scope metadata is descriptive, never a local authorization grant; Atlas enforces actual access. Implement future native adapters under the same stable destination IDs without changing the information architecture.
- Coverage includes the Rust graph/ABI tests, `ios/Tests/AtlasCoreTests.swift`, and fixture-backed `AtlasWorkspaceUITests` / Android workspace model checks and `capture_android.py --workspace`. Keep fixtures outside production source globs; see `previews/AGENTS.md`.

## Native business records and Profile

- People is a native Browse destination. The shared Rust auth crate owns the persistent Phoenix WSS connection, location validation, heartbeats/reconnect and latest-only event delivery; Swift/Kotlin models only bridge events and app lifecycle. Foreground clients report the current allowlisted page/record, clear stale same-page hints on navigation, and close on background/sign-out. Refresh/persist OAuth credentials through the existing coordinator before opening, never serialize blocking event waits with credential or business work. Presence describes viewing, not editing, and grants no write permissions. Server coordination and privacy rules live in [Atlas presence](../atlas/lib/atlas/presence/AGENTS.md).
- `auth/src/business.rs` allowlists resources, actions, fields, IDs and dates for `/api/native/tasks`, `/api/native/accounts`, `/api/native/invoices`, and read-only `/api/native/profile`. See the [server contract](../atlas/lib/atlas_web/controllers/AGENTS.md). Missing optional record values are empty strings; mutation attributes are strings, with empty strings clearing optional fields. Task completion is a dedicated action, never an editable status.
- `AtlasBusiness` / `AtlasBusinessModel` accumulate list pages as users scroll. Preserve rows and scroll position on append, deduplicate IDs, stop automatic retries after a failed next page, and reset pagination on search/filter/refresh. New criteria supersede in-flight reads; late results must never restore old rows or errors. Preserve a successful mutation when the following refresh fails, prevent double submission, confirm deletions/discards, and retain drafts on failure. Use native date/time controls, locale-safe amounts, and server-provided enum/relationship options.
- Business filters use native menus/pickers on iOS and toolbar menus/selection dialogs on Android. Apply filters on the server before count/pagination, never just to the loaded page. Task grouping consumes `fields.reminder_group` with server-wide overdue/upcoming/none/completed ordering; overdue means an open task with an expired `remind_at`, not a past `due_on`. Display active filters and a reset action. Keep invoice summaries unfiltered.
- Account rows/detail reuse the web app's Google S2 domain favicon endpoint with URL-encoded `primary_domain`, decorative rounded images and initials fallback. Image requests are credential-free and independent of Atlas OAuth transport; missing/failed logos must not block the list. Android image work is bounded and detached when rows leave the screen.
- Finance is manual invoice bookkeeping, not bank administration or payments. Imported/linked invoices are read-only even for finance writers. Monthly charts use the server's unpaginated, unfiltered summary and keep currencies separate. Use Swift Charts on iOS and accessible platform Canvas plus exact textual values on Android; do not call invoice totals cashflow or balances.
- Profile follows Tuist iOS's grouped identity/email/version/sign-out layout, adding the selected server URL, authenticated server version, and existing Claude/ChatGPT settings. Display the server-reported application version, never a protocol constant or invented revision. Profile does not grant identity or server configuration writes.

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
  production Swift sources; do not ship screenshot fixtures. CI device builds use
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
  steps do not. Sign the device IPA before uploading any platform, so a signing
  failure cannot publish a simulator-only nightly. Simulator uploads set
  `TUIST_PREVIEW_BUILD_VERSION` to a fresh Unix timestamp, avoiding duplicate
  previews without modifying the bundle or Once's cache. Device packaging already
  stamps its temporary copy before distribution signing. Credential-free packaging
  tests gate publication alongside the build, test and lint jobs. Forks use local caching
  and no OIDC; no PR publishes previews or receives distribution credentials.
