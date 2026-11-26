# Luft

Luft is a client developed alongside the shipping apps in `../app/` and `../android/`, not a replacement or a store release. Its independent Struo graph reports to [tuist/luft](https://tuist.dev/tuist/luft); GPUI provides the Linux/Windows UI, SwiftUI provides iOS/macOS interfaces, and Kotlin provides the Android interface. Native profiles, OAuth, session selection, and preview API operations are implemented in `crates/core`, reusing the existing Rust OAuth/PKCE and JWT logic.

The native apps use the Android package ID `dev.tuist.guild` and the iOS/macOS bundle ID `dev.tuist.code` (kept so the existing App ID and signing profiles keep working), display as **Luft**, and register `luft://oauth-callback` for authentication and `luft://app/…` for navigation, not the shipping `tuist:` scheme, associated domains or updater feeds. iOS and macOS receive push notifications through APNs on the `dev.tuist.code` topic (see [Push notifications](#push-notifications)). They do not read or modify shipping-client credentials, so they never trigger Keychain prompts for the Tuist app's items or sign anyone out of it. The GPUI client uses the `dev.tuist.guild` application ID and isolated Luft credential directories, not the CLI's saved credentials or selected server.

## Build

Run from this directory. Exclude the root mise configuration so the CLI toolchain/bootstrap is not installed for Luft:

```sh
export MISE_IGNORED_CONFIG_PATHS="$(git rev-parse --show-toplevel)/mise.toml"
mise trust
mise install
struo auth login --provider tuist
mise run test:core
mise run build:ios
mise run build:ios-device
mise run build:macos
mise run build:android
mise run build
mise run test
```

These commands upload build/test insights and use the hosted `tuist/luft` cache. Set `STRUO_CACHE_PROVIDER=local` for credential-free offline builds instead. Cache reuse requires the same platform, toolchain, and build inputs; warm local outputs alone do not demonstrate remote reuse.

For a signed-out iOS motion study, launch the simulator app with
`-LuftSandboxPreview`. It uses the native conversation components and readiness
overlay with a clearly labeled, simulated two-second sandbox startup, not a
real VM. Add `-LuftSandboxLight` or `-LuftSandboxFailure` to capture those states;
the preview also offers replay, failure and appearance controls. The overlay
respects the simulator's Reduced Motion accessibility setting.

Struo 1.0.0 reads `struo.toml`, writes `.struo/`, and uses `STRUO_*` settings and separate XDG state/cache directories. It does not migrate Once's local outputs or credentials. Rebuild and sign in again instead of copying `.once/out`; the hosted `tuist/luft` identity is unchanged. Historical checksum-pinned Once provider URLs in `modules/` remain adaptation provenance.

Apple builds require Apple Silicon macOS/Xcode and `rustup target add aarch64-apple-ios-sim aarch64-apple-ios`. Android needs Java 17+, Kotlin, compile SDK 36 (target SDK remains 35), build-tools 35.0.0, `ANDROID_HOME`, `ANDROID_NDK_HOME`, `rustup target add aarch64-linux-android`, and a local debug keystore. Struo resolves the NDK linker from `ANDROID_NDK_HOME`; C build scripts, such as bundled SQLite's, also need the NDK's `toolchains/llvm/prebuilt/<host>/bin` on `PATH`. Python 3.11+ is required for preparation. Build products live under `.struo/out/<target>/`: `LuftIOS`, `LuftIOSDevice`, `LuftMacOS`, and `LuftAndroid`. The iOS device output is ad-hoc signed; `mise run bundle:ios-device` signs an installable copy for registered devices (see [Signed device previews](#signed-device-previews)). Simulator-only entitlements give its separate preview sandbox Keychain access.

Swift imports the core's C module, Kotlin calls its JNI bridge, and the existing Rust navigation crate re-exports the same `Tab` type. GPUI and its dependency graph are not in the native frontend build closures. Platform code supplies localized presentation, browser callbacks, secure storage and ordinary platform-trusted HTTPS; Rust owns authentication, refresh and authorized API operations, without its own mobile HTTP/TLS stack. See [the bridge contract](crates/core/README.md).

Mise runs `prepare-native.py` before graph loading. When invoking Struo directly, run `python3 prepare-native.py` first. This derives an ignored metadata-only Cargo workspace and vendors its dependencies, avoiding desktop feature unification and generated-target collisions in Once 0.77 and later. Every external version/source/checksum must match the authoritative `Cargo.lock`; first-party compilation always uses the original `crates/` sources, never the metadata stubs. Preparation may download missing crates. For Android, additionally run `python3 android/dependencies.py prepare`; its checksum-locked AndroidX Browser closure and final-APK resource verification are documented in [Android dependencies](android/DEPENDENCIES.md).

## Web edge

`web/` retains the standalone browser edge for future work; it is not deployed at `luft.work`. The Luft server (`../luft-server/`) serves headless JSON APIs and OAuth redirects, with no HTML shell, static assets or Vite proxy. The standalone edge follows the same split as the native edges: the core runs as wasm in a Web Worker, because its host calls are synchronous and browsers allow synchronous XHR and OPFS file handles only in workers, and TypeScript renders what it reports. Struo builds it in three cacheable steps: `LuftCoreWasm` compiles `crates/web` (thin `wasm_bindgen` exports over the core) for `wasm32-unknown-unknown`, `LuftCoreBindings` runs the wasm-bindgen CLI, and `LuftWeb` runs `npm ci` and `vite build` (`modules/web.star`). `crates/web` enables the browser backends for `getrandom` and `sqlite-wasm-rs`; the core itself stays free of `wasm-bindgen`.

```sh
rustup target add wasm32-unknown-unknown
mise run dev:web     # Vite dev server on 5173; rerun after core changes
mise run build:web   # standalone output: .struo/out/LuftWeb/dist
```

The wasm-bindgen CLI in `mise.toml` must match the `wasm-bindgen` crate in `Cargo.lock`. These commands run the standalone web tooling only. `mix phx.server` does not start Vite, and `.github/workflows/luft-server-deployment.yml` neither builds nor packages the web output. A deployed browser frontend and its API/session integration remain future work.

## Native profiles, authentication and sessions

Every client's signed-out screen copies the shipping app's `LogInView`, titled **Welcome to Luft** (`../app/Sources/TuistOnboarding/LogInView.swift`, `../android/app/src/main/java/dev/tuist/app/ui/login/LoginScreen.kt`): Sign in with Tuist, Apple, Google and GitHub through `https://luft.work`, then **Self-hosted server**, which asks for an HTTPS Luft server URL and prefills the last self-hosted server used. GPUI shows the social providers only while `https://luft.work` is selected, signs in through the selected Luft server, and opens its account/server form from **Self-hosted server**. Its artwork and brand assets are copied into `apple/Resources/Assets.xcassets` and `android/res/`; GPUI keeps its theme colors. On iOS, macOS and Android, adding a profile shows the same screen with Cancel; GPUI adds accounts from its account menu. The screen scrolls when a landscape phone or large text leaves too little height. Every client keeps several accounts, on one or more Luft servers, and switches between them without signing in again.

Signed in, iOS, macOS and GPUI share two destinations from the core's tab catalog: **Threads**, then **Profile**. iOS shows one destination at a time, the one the core's `navigation.tab` and stacks say is open, so links and notifications land in the same place. Like Claude's app, a sidebar slides over it from the toolbar's sidebar button or an edge swipe: **Lounges** and **DMs** rows above the threads, and, floating over the threads as in Claude, the account's initial (Profile), a **Search** pill that opens the Jump To palette, and a compose button for **New conversation**; picking one closes it. With no thread open, the main area is a new chat, like Claude's: its composer asks what to talk about and sending starts the conversation, in place of the Mac's Start conversation sheet; the core's `/threads/new` route raises its keyboard, or dictation for `/threads/new/dictation`. Navigation bars adopt Liquid Glass on iOS 26 and later, with the account menu in Profile's navigation bar; conversations float the reply field over the messages (in glass on iOS 26 and later). macOS follows the HIG with a `NavigationSplitView` sidebar, a toolbar account menu and a grouped-form Profile, and **View ▸ Jump To…** (⌘K, as in Slack and the dashboard) opens a palette that finds destinations, New conversation, threads, lounges and DMs through the core's `palette`; it builds from the same SwiftUI sources as iOS (`apple/Sources`), and only the Info.plist differs. GPUI follows Zed's workspace: a left dock of destinations under the title bar's account menu. On iOS and macOS, Threads lists the person's own threads in the account selected in the account menu, from `/api/accounts/{personal account or organization}/threads`, grouped into In progress, Recent, Snoozed and Archived by the core; GPUI lists the same threads through the core's `Threads` operations. On iOS and macOS a thread can be snoozed from its row (swipe or context menu), from its conversation's toolbar, and from the Live Activity, whose Snooze opens the thread's choices (`/threads/{id}/snooze`): until it's needed (only while it works: until its run stops), in 1, 2 or 4 hours, this evening, tomorrow, next week, or at a picked time up to 30 days ahead, from the core's `snooze_options`. A snoozed thread moves to Snoozed and out of the Live Activity, and a timed snooze stays quiet until its time, when the server reminds the person; writing to the thread wakes it. GPUI and Android can't snooze yet and list snoozed threads with the rest. The server answers 404 when threads are off for the user (its `code` flag) or it predates them; the core reports `available: false` and the tab explains it. An organization's threads need admin rights there and the organization's `luft` flag; the server answers 404 without them too. Native clients authorize to Luft; the Luft server calls Tuist with the scoped `luft:app` capability and the person's permissions. A 401/403 becomes `reason: "sign_in_required"`; iOS, macOS and Android offer **Sign In Again**, and GPUI asks to sign out and sign in again. New upstream scopes require a fresh Luft sign-in. Every client keeps what it has seen in a local SQLite store (see `crates/core/README.md`), so threads stay readable offline, and threads and replies written offline are sent when the connection returns. Every client, Android included, starts a conversation with **Start conversation**: it asks only what to talk about, and the conversation runs on the server, with no repository or model to choose; on iOS and macOS a **Run on** picker also offers the person's runners (see Runner), labelling offline ones. The server refuses a thread on a runner that is offline, and the core refuses one while the device is offline instead of queueing it, since the outbox replays only a thread's text. Opening a thread shows its messages, keeps them current while the server answers, and accepts replies. On iOS and macOS, the conversation view follows Atlas: the reply field offers dictation with Apple Speech's on-device recognition only (hold the microphone and release, or tap to start and stop; the transcript is added to the editable reply and never sent automatically, and audio never leaves the device), a Prompts index (in the toolbar on macOS, floating above Send on iOS) jumps back to any of the person's earlier messages and loads earlier history on request, and tool calls render as collapsed evidence showing each tool's name, whether it is running, and its result. On iOS, two App Shortcuts (Shortcuts, Siri and the Action button) open **Start conversation** directly by navigating to the core's `/threads/new` route (`/threads/new/dictation` for dictation), which waits for sign-in like any link: **Start Conversation** with the keyboard up, and **Dictate Conversation** with dictation already recording; neither starts the conversation until the person sends it. Struo has no App Intents step, so `modules/appintents.sh` compiles the self-contained `apple/Sources/AppShortcuts.swift` after each iOS build and writes the `Metadata.appintents` that Shortcuts reads. The Developer ID copy is signed with the hardened runtime's microphone exception (`macos/distribution/entitlements.plist`). The account menu (on Android, Profile's **Switch account**) lists the personal accounts and organizations of every saved profile from the core's `accounts` view; choosing one switches to the profile that owns it. It also adds a profile and signs out. Profile copies the shipping app's `ProfileView`: identity, email, server, legal and help links, app version, sign-out and confirmed account deletion.

Android still shows its earlier Previews/Profile interface: project selection, full-project track counts, server-side debounced search, pagination, detail metadata, full plain-text release notes and a confirmed HTTPS APK handoff. Every client supports saved profiles on one or more Luft servers and hosted/self-hosted sign-in. Authentication uses an ephemeral system browser, exact single-use callback/state validation, the static public Luft client and PKCE. Before opening the browser, Luft checks `/.well-known/luft.json` for `luft_oauth_client_id` equal to `6653b77b-b787-4eb2-b955-8380ea5f1478`; a Tuist server or other origin without this contract fails discovery. Android requires an ephemeral-capable Custom Tabs provider and fails closed when none is available.

All native defaults use `https://luft.work`; desktop `LUFT_URL` overrides the saved startup origin, not `TUIST_URL`. Native clients call the Luft server's `/oauth2/authorize`, `/oauth2/apple`, `/oauth2/google` or `/oauth2/github`, then `/oauth2/token`. Redirects must be exactly `luft://oauth-callback` or the desktop loopback `http://127.0.0.1:<port>/callback`. The Luft server brokers Tuist OIDC and returns signed Luft access JWTs (`iss=luft`, up to one hour) plus opaque rotating refresh tokens backed by 30-day sessions. It keeps encrypted Tuist tokens server-side and owns threads, lounges and DMs in its own database. Clients use `/api/accounts/{account}/lounges` for lounges and private direct conversations; the JSON separates `lounges` (`kind: "lounge"`) from `directs` (`kind: "direct"`). The server brokers Tuist data for previews, projects and accounts. Preview links and media use Luft URLs, while object-storage URLs stay unchanged. See [the server contract](../luft-server/README.md) for upstream scopes and the retained browser cookie flow.

Session storage follows the existing platform boundaries, but not the shipping app's sandbox:

- **iOS/macOS:** Keychain generic-password service `dev.tuist.code.profiles`, account `profiles-v1`, non-synchronizing `AfterFirstUnlockThisDeviceOnly`. No desktop session files are used.
- **Android:** private `shared_prefs/tuist_secure_prefs.xml`, key `vault`, containing one AES-GCM encrypted record. The encryption key stays in Android Keystore under `tuist_luft_vault`; backup and device transfer are disabled. The application sandbox locates the preferences file, never a hard-coded `/data` path.

Rust treats the vault as private, never sends credentials in view snapshots, binds refreshes to the issuing origin/client, persists selection before publication, and retains rotated credentials in memory until a failed durable write can be retried. An interrupted process cannot preserve a memory-only rotation. Profile/organization changes discard stale native navigation and API results. There is no credential migration from current clients.

Mobile vault migration drops any old profile whose access token lacks `iss=luft` and writes the vault back, so users sign in to Luft again. This includes earlier macOS previews that used the Tuist app's Keychain session. Luft does not touch the shipping app's Keychain items or reuse legacy CLI files; the Tuist app stays signed in.

CI authenticates trusted builds through GitHub OIDC for hosted caches and insights; forks use local caches without login. The isolated optimized Linux/Windows packaging step still uses a local cache. CI retains unsigned/unprovisioned workflow artifacts. There are no store uploads, public release jobs or enabled new-client updater keys. The private hosted project is linked to `tuist/tuist`.

## Cards in conversations

A message can carry a card the model wrote: NSH JavaScript the iOS app runs in an embedded `NshAppView` from NSH's checksum-pinned release SDK (`modules/nsh.star`), at the height the core chose for its size class (see `thread` in [the bridge contract](crates/core/README.md)). Cards run with a small VM, their own disposable storage and one host function, `reply`, which puts text in the composer for the person to send. A card composes only Luft's card kit (`../server/priv/threads/card_kit.tsx`, imported as `./luft`): stacks, titles, stats, meters, rows, badges and reply actions with no styling props of their own, which take the selected theme's colors (the core's `card` theme overrides) and draw actions as Liquid Glass on iOS and macOS 26. The app draws the card's glass surface. macOS and GPUI have no NSH runtime yet and show the message's text. Launch the iOS simulator app with `-LuftCardPreview` to see `cards/bundle.js` in a signed-out conversation; rebuild it from `cards/App.tsx` with `NSH_BIN=… cards/build.sh`, which also runs it headless. The server's `show_ui` tool (`../server/lib/tuist/threads/cards.ex`) builds and checks the cards models write before sending them; keep its frame heights in step with the core's.

Structured decisions are separate from model-authored `show_ui` cards. An assistant message preserves `decision: {question, options:[{id,label}], allow_other, status, answer}` in the core and local store, with `status` `pending`, `answered` or `cancelled`, and `answer` null or `{option_id,text}` (the option ID is null for free text). Pending decisions may carry a server-generated `medium` card (240 points) using `mount(() => <Decision question={…} options={…} allowOther={…}/>)` from `./luft`. The kit scrolls long content and wraps option labels without truncation; only pressing an option calls `host.call("answer", option.id)`. Swift grants this capability only to pending decision cards, validates the ID against that message's options, and calls the core's online-only `answer_question` operation with the message UUID and chosen label. Generic card `reply` calls still only edit the composer and can never submit an answer directly. Native macOS, and iOS when NSH fails or no card is present, render working native option buttons; SwiftUI also provides Dismiss, a composer hint when other answers are allowed, busy state and errors. Answered/cancelled decisions display the question and recorded choice/dismissal with no active buttons or JS. Normal composer replies answer the latest pending decision on the server.

The signed-out `-LuftCardPreview` simulator conversation includes a pending decision using `cards/decision-bundle.js`, an intentionally failing card to exercise native fallback, and answered/cancelled decisions. The same launch flag on macOS exercises the native fallback. Use `-LuftDecisionPreview` for a single pending question when checking option selection, free-text replies and dismissal. Generic card actions fill its composer rather than directly appending a message. `NSH_BIN=… cards/build.sh` builds both preview bundles from the same server kit and runs focused NSH headless tests for press-only option IDs and composer-only generic replies.

## Internal previews

After building, explicitly publish the simulator, native macOS or Android APK with `mise run preview:ios`, `mise run preview:macos`, or `mise run preview:android`. Each publishes to the private project's `internal` track. Builds and tests do not automatically publish previews. The **Luft** workflow (`.github/workflows/luft.yml`) publishes these three artifacts on every push to `main` that touches Luft, and on a manual run on `main` with `publish_previews` enabled; it never publishes from pull requests. The existing shipping-client build workflow remains **App** (`app.yml`). Those runs also sign and publish an iOS device IPA; see below. The macOS job publishes a copy signed with Tuist's existing **Developer ID Application** certificate and notarized with its Apple account (`macos/distribution/bundle.sh`, then `mise run preview:macos`), reading both from the same 1Password items as Atlas; `mise run preview:macos` therefore needs `mise run bundle:macos` first. Android uses a development debug key, not a stable distribution identity, so previews from different machines may require uninstalling the previous debug app.

### Updating to a newer preview

Signed in, iOS, macOS and Android check through `https://luft.work` for a newer internal preview when a profile becomes active and whenever the app returns to the foreground (core operation `preview_update`), using a saved luft.work profile. The private project remains on Tuist; the Luft server proxies its preview API and rewrites preview/media links while preserving object-storage URLs. The edge identifies its own build: the executable's Mach-O UUID on Apple platforms, which `tuist share` records for the IPA and Developer ID app, and the installed APK's SHA-256 on Android, which the server now records for Struo-published APKs. A newer build asks once per launch to update now, so people stay on the latest preview, with **Update** and **Later**; Profile keeps a **New version available** row with an **Update** button under App version. iOS opens the preview's over-the-air manifest, so the device must be in the Tuist Code Ad Hoc profile; Android hands the APK download to the browser and the system installer, and debug keys from different machines still require uninstalling first; macOS downloads the app, accepts it only when it carries Tuist's Developer ID and the `dev.tuist.code` identifier, and replaces and reopens itself after quitting. The simulator build skips the check because it cannot install device builds. GPUI keeps its signed release updater: no GPUI previews are published.

### Signed device previews

Device previews use ad-hoc distribution. `ios/distribution/bundle.sh` copies the Struo device build, validates the Tuist Code Ad Hoc profile and the Live Activity extension's own Tuist Code Live Activity Ad Hoc profile, embeds them, signs the extension and then the app with the shared **Apple Distribution** certificate in a disposable keychain, and writes `delivery/ios-device/Luft.ipa`. `mise run preview:ios-device` publishes it with the Tuist CLI (configured by `tuist.toml`) to the `internal` track. Struo's own outputs and cache never receive distribution signatures or keys.

One-time setup in Apple Developer (Tuist GmbH, team `U6LC622NKF`):

1. Register the explicit App ID `dev.tuist.code`. It needs no capabilities.
2. Create an **Ad Hoc** profile named **Tuist Code Ad Hoc** for it, selecting the existing Apple Distribution certificate (the one in the `Distribution Certificate` 1Password item) and every registered team device.
3. Store the downloaded profile as a document item named `Tuist Code Ad Hoc` with file name `Tuist_Code_Ad_Hoc.mobileprovision` in the `tuist` 1Password vault, which the CI service account already reads.
4. Register the explicit App ID `dev.tuist.code.live-activity` for the Live Activity extension (no capabilities), create an **Ad Hoc** profile for it with the same certificate and every device in **Tuist Code Ad Hoc**, and store it as a document item named `Tuist Code Live Activity Ad Hoc` with file name `Tuist_Code_Live_Activity_Ad_Hoc.mobileprovision` in the same vault. `bundle.sh` refuses to sign without it, and checks its team, expiry, devices and certificate before reading the private key. The extension is signed with only its identity entitlements, never the app's APNs or Keychain ones.

Regenerate and replace both profiles when adding devices or renewing the certificate; a device missing from either cannot install the IPA. Locally, with 1Password access: `mise run bundle:ios-device && mise run preview:ios-device`.

Linux executables built through Struo can be published with the Tuist CLI's `share` command using an isolated `tuist.toml` containing `project = "tuist/luft"` and `--track internal`. Do not invoke `share` against the root `Tuist.swift`, which belongs to the shipping clients. Struo's Rust binary target does not yet export native artifact metadata, so the native `struo artifact publish` tasks do not cover GPUI. Windows packaging remains in CI; neither a local MSVC build nor hosted Windows preview publication has been verified. The server currently projects executable previews only for Linux and macOS.

## Icons and names

Native Apple/Android bundles declare **Luft** as their display name and use isolated identities: `dev.tuist.code` on Apple platforms, `dev.tuist.guild` on Android. Their icons are the shipping `../app/Resources/TuistApp/AppIcon.icon` layers on a dark editor background, so Luft is distinguishable from the shipping app; regenerate the checked-in raster/ICNS resources on a Mac with Xcode 26+ using `bash apple/generate-icons.sh`. Shipping resources are read-only inputs. Explicit PNG/ICNS resources keep icons in Struo's cached outputs, including the iOS fallback icons.

Struo (0.81.0 and later) publishes each Apple and Android bundle's icon and display name with the artifact, and the server shows them on the preview. Raw Linux executable previews published with `tuist share` are labeled CLI regardless of whether they open a GUI; pass `--icon gpui/resources/rounded-icon.png` to give them the app icon. Bundle icon changes do not repair existing hosted previews; a fresh upload is needed.

## GPUI frontend

Build the Linux/Windows frontend through Struo with `mise run build`, then launch with `mise run run`. macOS remains a GPUI development host; the native Swift macOS target is the new Apple frontend. This is an early shell, not a replacement for the shipping Swift app's preview browsing or installation features.

The dock lists **Threads**, **Lounges**, **DMs** and **Profile**, the core's tab catalog. Lounges are an organization's named, long-lived conversations (`#name`) that every member reads and writes; DMs are direct conversations between 2 to 8 people. Neither has an agent. Both lists show each conversation's title, latest message and unread count; **New lounge** asks for a name and an optional topic, and **New message** picks people from the organization. An open conversation shows its messages oldest first with author and time (UTC), rereads the server every 3 seconds while it is visible in the active window, and marks what it shows read only then. They run through the core's `Lounges` operations (`gpui/src/workspace/lounges.rs`); reads each use their own `Lounges`, so they never wait behind a send, which keeps its idempotency key in a shared one. Because the desktop account menu selects profiles rather than organizations, Lounges and DMs share their own organization choice from the core's `organizations`, the person's first organization by default, with a picker when there are several; a failed lookup retries on the next poll or from **Refresh**, and a personal account without organizations sees that lounges belong to organizations. While the window is active, the app stays joined to the organization's presence through the core's `Presence` over a WebSocket on its own thread (`gpui/src/workspace/socket.rs`, tungstenite with rustls and the platform's root certificates, like the app's HTTPS), and leaves it when the window deactivates, on sign-out and when switching accounts. A green dot marks people who have Luft open: in DM rows, a DM's members, message authors and the New message picker; without a live presence connection, the server's `online` stands. Ctrl+1 to Ctrl+4 (Cmd on the macOS development host) select the dock's destinations in order, also from the account menu or settings, and move focus to that destination's dock row.

The GPUI source layout uses Struo's `build_script_sources` support, originally included in
Once 0.77.5; the workspace pins [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0).
That support also aligns build-script debug assertions with optimized crates,
which GPUI needs to generate shaders for Windows packaging.
Run `mise install` to install the published toolchain before building.

## Servers and accounts

Open the avatar at the top right of the application title bar to switch directly
between saved profiles, view your profile, sign out, or open app settings. The
menu shows the server alongside each account and marks the current profile.
Use **Add account or server…** (also available as **Self-hosted server** and
**Saved accounts…** on the welcome screen). Enter `https://luft.work` or an HTTPS self-hosted
Luft server URL, then complete browser sign-in. Multiple logins on the same server
and accounts on different servers are retained; selecting a saved account does
not require another browser sign-in unless its credentials have expired or been
rejected. Self-hosted servers use their own sign-in page, not assumed social
providers. The browser's current login determines the account being added;
sign out in the browser first when adding a different identity on that server.

The title bar is application-level chrome, separate from the workspace sidebar
and its selected content. Its layout follows Zed's avatar/popover pattern,
adapted to the pinned GPUI version. Initials are used because the shared token
contract does not provide a verified avatar image URL; no third-party avatar
service receives account email addresses. Open the menu with Ctrl+Shift+A
(Cmd+Shift+A on the macOS development build), move with Up/Down or Home/End,
activate with Enter/Space, and dismiss with Escape, Tab, or an outside click.
App settings describe system-following appearance and expose manual update checks.

The avatar is intentionally absent from sign-in and account-entry screens.
Saved accounts remain reachable through **Saved accounts…** on sign-in.

## Keyboard access and accessibility

Tab and Shift-Tab move through enabled controls in visual order, with a visible
focus border. Enter or Space activates a focused button; focusing an off-screen
control scrolls it into view. This covers sign-in providers, account/server entry,
workspace navigation, preview actions, settings, sign-out, error dismissal and
manual update checks. Text entry retains its normal editing and clipboard keys;
Enter submits the server form. Escape cancels browser sign-in or closes the account
form/settings. These screens are pages, not modal dialogs.

The account menu uses arrows and Home/End, Enter/Space activation, Escape to
restore the opener, and Tab/Shift-Tab to close and leave the menu. Ctrl+1 to
Ctrl+4 select Threads, Lounges, DMs and Profile and focus that dock row. Application
shortcuts use Ctrl on Linux/Windows and Cmd on macOS. Native system window-management
shortcuts remain platform-owned.

Behavior follows the [WAI-ARIA APG button](https://www.w3.org/WAI/ARIA/apg/patterns/button/),
[menu](https://www.w3.org/WAI/ARIA/apg/patterns/menubar/) and
[menu-button](https://www.w3.org/WAI/ARIA/apg/patterns/menu-button/) conventions,
[Microsoft keyboard guidance](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-interactions),
and [Apple keyboard navigation](https://support.apple.com/guide/mac-help/use-full-keyboard-access-mchlc06d1059/mac).
These are behavioral references, not ARIA attributes on a native GPUI view.

GPUI and its platform adapters are pinned to Zed revision
`b5cd310b3b54dfc659fcc06453e6358843dfe216`, with the
[AccessKit bridge](https://github.com/zed-industries/zed/pull/56065) enabled for
native accessibility. Controls expose names, roles and state; the server field
exposes editable text, caret/selection and assistive editing actions. Status and
error messages use live regions, and covered content is hidden from the
accessibility tree while transient UI is open.

Native macOS AX checks exercised actual adapter actions with isolated fake
accounts: server-field focus/value/Unicode selection, invalid submission,
switching the 30th account in an overflowing menu, settings, sign-out, and hiding
covered content. A held registry lock verified that busy work moves focus out
of the hidden field. These checks do not verify spoken screen-reader output.

Native acceptance must separately cover VoiceOver on the macOS development
build, Narrator/NVDA on Windows, and Orca on Linux: navigate sign-in and accounts,
edit and select a Unicode server URL, submit an invalid URL, switch profiles,
operate the account menu/settings, and hear asynchronous status/error updates.
GPUI's headless test platform does not activate AccessKit, so constructed-node,
input-listener and keyboard tests alone do not establish compatibility with
these screen readers.

## Session persistence

The last selected Luft server survives restarts. An explicit `LUFT_URL` overrides
that startup selection, but startup fails closed if another full server URL
owns the same host's canonical credentials. Switching accounts clears preview/detail navigation
and pending links rather than delivering a previous account's route to the new
session. Signing out removes the selected account, not every saved login.

`Directories::from_env` appends `/luft` to the config, state and data base directories. The active credentials keep the existing JSON format and host-only identity at `<config>/credentials/<normalized-host>.json`, but use this separate Luft namespace. No legacy CLI credentials or selected Tuist origin are reused. Selecting another login on a host changes Luft's active credentials for that host. Rotation and switching use Luft's refresh lock; the latest canonical tokens win over an older desktop snapshot.

| Platform | Active credentials | Additional desktop accounts |
| --- | --- | --- |
| macOS development | `~/.config/tuist/luft/credentials/` | `~/.config/tuist/luft/desktop/accounts.json` |
| Linux | `~/.config/tuist/luft/credentials/` | `$XDG_DATA_HOME/tuist/luft/desktop/accounts.json`, default `~/.local/share/tuist/luft/desktop/accounts.json` |
| Windows | `%LOCALAPPDATA%/tuist/luft/credentials/` | `%LOCALAPPDATA%/tuist/luft/desktop/accounts.json` |

macOS honors `TUIST_XDG_CONFIG_HOME`/`XDG_CONFIG_HOME` for both locations.
Desktop account data honors `TUIST_XDG_DATA_HOME`/`XDG_DATA_HOME` on Linux and
Windows. Locks honor the corresponding state-home variables, with macOS/Linux
defaulting to `~/.local/state/tuist/luft`, and Windows to `%LOCALAPPDATA%/tuist/luft`.
Only absolute overrides apply, and `TUIST_` takes precedence over plain XDG.
These directory-variable names remain unchanged; `Directories::from_env` appends `luft` after resolving them. `TUIST_URL` does not select the Luft server. Windows credentials are local, never placed in roaming `%APPDATA%` by default.

Saved account files contain Luft access and refresh tokens, like the isolated canonical
file. They are atomically replaced and private (`0600` on Unix; Windows inherits
the user's local application-data directory permissions). They are not
encrypted by an OS credential vault. Do not sync, share, or commit these files.
The retained credential file format distinguishes hosts, not ports or URL
base paths. The desktop registry tracks which full server URL owns each host's
active file, so switching through another host cannot overwrite an inactive
deployment's saved login. Older registries infer ownership only from a sole
profile or an unambiguous exact credential match; otherwise snapshots stay intact
until explicit sign-in or account selection establishes ownership. Out-of-band
edits to Luft's canonical file for another deployment on the same host remain indistinguishable because that file contains no full issuer URL. CLI sign-in uses a different directory and cannot change these files.

## Runner

The runner lets threads work on this machine. `crates/runner` builds `luft-runner`, a std-only Rust daemon meant for every desktop app; today only the macOS app bundles it, as `Contents/MacOS/luft-runner` (`LuftRunnerMacOS`, wrapped by `modules/runner.star` and copied in by the app's prepackage action; `macos/distribution/bundle.sh` signs it before the app). On macOS, **Luft ▸ Settings… ▸ Runner** drives it through its command line, which prints JSON: `status`, `install` (a launchd agent `dev.tuist.guild.runner` that starts at login and restarts on exit; a systemd user unit on Linux and a logon task on Windows, both untested so far), `uninstall`, `set <key> <value>`, `reset` and `request-permissions`. The service manager starts `run`.

Settings live in `config.json` in the state directory (`~/Library/Application Support/dev.tuist.guild/Runner` on macOS; `LUFT_RUNNER_HOME` overrides it): the runner name, its folders, the new project folder (which must be inside one of them), display sharing, terminal access, portals (stored and reported but not offered in Settings, since nothing uses them yet), and keeping the Mac awake (`caffeinate -s`, on power only). A new runner shares one projects folder (`~/Developer` on macOS, `~/projects` elsewhere, which `install` creates) with terminal access, display sharing and portals off. The daemon rereads it every five seconds and before every operation; when the file can't be read (half-written, from a newer app, or deleted after it loaded once) it keeps the last settings it read, or shares nothing if it never read any. `status` then reports `config_error` with no folders or permissions, and `reset` writes the defaults. The daemon writes a heartbeat to `status.json`, which the app reads; the log is `~/Library/Logs/Luft/runner.log`.

Operations (`src/ops.rs`: `info`, `read_file`, `write_file`, `list_dir`, `exec`, and the display operations `screenshot`, `mouse_move`, `click`, `scroll`, `type_text`, `key`) are JSON requests whose paths must resolve, symlinks included, inside the runner's folders and outside its state directory and log folder, which hold its settings and secret. `exec` needs terminal access and display operations need display sharing; those two are not confined to the folders: a command only starts in one, and display control reaches the whole screen. `exec` runs the command in its own process group, kills the group on timeout, and answers once the shell exits, leaving background jobs such as a dev server running. Text with NUL is sent as base64 (`read_file`) or with NUL shown as `␀` (`exec` output), because the server stores requests as `jsonb`. `luft-runner serve-stdio` runs them from standard input for local testing. Settings ▸ Runner ▸ Connection registers the runner through the core (`register_runner`, `POST /api/me/thread-runners`, which returns an encrypted `luft_runner_…` wrapper bound to the Luft session) and hands it to `luft-runner connect <server> <runner-id>` on standard input; `disconnect` forgets it. The upstream `tgr_…` secret stays inside the wrapper; the runner sends only the wrapper to the Luft origin. The secret stays in a 0600 `connection.curlrc` and `connection.json` keeps the server and runner ID. The daemon long-polls `POST /api/thread-runner/poll` and answers with `POST /api/thread-runner/requests/:id/response` through the system `curl` (HTTPS only, except localhost), and reports `connection` as `not_connected`, `connecting`, `connected`, `offline` or `unauthorized`. On the Tuist upstream, requests are rows in `thread_runner_requests`, claimed with `FOR UPDATE SKIP LOCKED` and woken through PubSub, so any replica can serve the runner and the thread. Every poll lists the requests the daemon received and hasn't delivered an answer for (`in_flight`, also kept in `in-flight.json`); one claimed more than ten seconds earlier that it doesn't list never reached it, and goes back to the queue. The daemon retries an answer that fails to arrive (no network, a 5xx) for up to 40 minutes, keeping its request listed meanwhile, and a restarted daemon answers what its predecessor left unanswered with an error rather than running it again, so a command never runs twice. The server refuses to start a thread on a runner that hasn't polled in the last minute (409, `reason: "runner_offline"`). A thread started with a `runner_id` runs its Read, Ls, Write and Edit tools (Bash with terminal access, `display_*` with display sharing) on the runner through `Tuist.Threads.RunnerSandbox`, starting in the runner's new project folder. Sharing the network connection and sharing with the workspace are not implemented.

macOS grants Screen Recording and Accessibility to the daemon, which launchd starts as its own responsible process, not to Luft: a process the app spawns is checked against the app's grants. The daemon therefore reports its grants in its heartbeat and asks for them itself, when display sharing is turned on or when the app writes the `request-permissions` marker.

## Reusable Rust core

The workspace stays horizontal: `app` is the only crate that depends on GPUI.
JWT claims, credential storage/locking, OAuth/PKCE and loopback authentication,
session/account orchestration, navigation, and signed updates each have their
own library crate. `tuist-session` composes `tuist-jwt`, `tuist-credentials`, and
`tuist-oauth`; none depends on a view, window, or desktop application state.
The session layer's `AuthorizationServer` trait separates token operations
from their transport, while the UI owns browser opening, background scheduling,
and routing. Credentials take explicit directories rather than requiring a UI.

These desktop APIs remain separate from the native C/JNI bridge in `crates/core`.
The native bridge reuses portable PKCE/JWT helpers without importing the GPUI shell,
desktop credential files, network stack or updater. Browser/callback integration
and secure-storage implementations remain platform-owned.

The Desktop CI builds/tests the GPUI shell and core natively on Linux, Windows,
and macOS. Only Linux AppImage and Windows NSIS are Rust release targets;
macOS remains the Swift app. A configured CI job is not evidence of a successful
native build until that job has actually run.

## Deep links

Luft has one typed route catalog in `crates/core/src/navigation.rs`, shared by iOS, macOS, Android and GPUI. No navigation library is required. The native edges render the core's selected tab and lightweight conversation identifier, rather than reconstructing a sequence of clicks. This follows Apple's [data-driven NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack), Android's [deep-link back-stack guidance](https://developer.android.com/guide/navigation/design/deep-link), and the enum/optional state modeling described by [Point-Free](https://www.pointfree.co/blog/posts/96-modern-swiftui-state-driven-navigation), without depending on their libraries.

| Path | Destination |
| --- | --- |
| `/threads` | Threads inbox, clearing the conversation stack |
| `/threads/new` | Start conversation over the Threads root, with the keyboard; closed by any other navigation |
| `/threads/new/dictation` | Start conversation with dictation started. Internal path only: the custom-scheme and web forms are rejected, so no other app or page can open the microphone |
| `/threads/{id}` | Conversation with a UUID identifier; Back returns to Threads |
| `/profile` | Profile |

Three representations resolve to the same destination:

- `/threads/{id}`: an internal/automation path scoped to the selected profile.
- `luft://app/threads/{id}`: an OS deep link scoped to `https://luft.work`. For a self-hosted Luft server, append `?server=<percent-encoded HTTPS server URL>`, including its base path.
- `https://<server>/<optional-base-path>/luft/threads/{id}`: the reserved web URL shape. There is no Luft web page or verified Universal Link/App Link domain yet; passing this URL to the app works, but clicking it in a browser does not yet launch Luft.

URLs received while signed out wait in memory for sign-in, then are checked against the signed-in server. The last valid pending link wins. Invalid, ambiguous and wrong-server links leave navigation unchanged. Links never sign in, change servers/accounts, create conversations, start dictation or send messages; `/threads/new` only opens the Start conversation form. Thread access remains server-authorized for the selected account. Switching profiles/organizations clears navigation; navigation is not persisted with credentials. Tab switches preserve the Threads stack, while `/threads` explicitly returns to its root. Reopening a conversation replaces its stack rather than adding duplicate screens.

### Launch directly into a destination

For agents, the catalog above is also available through the core's `routes` operation and the GPUI executable's `--list-routes`. Push notifications carry the scoped Luft web URL and are opened through `open_notification` (see [Push notifications](#push-notifications)), never UI gestures or arbitrary API actions.

```sh
# iOS simulator: cold launch with a path, or cold/warm delivery of a URL.
xcrun simctl launch booted dev.tuist.code --navigate /profile
xcrun simctl openurl booted 'luft://app/threads/12345678-1234-5678-9abc-123456789abc'

# macOS: launch arguments or OS delivery to the registered native bundle.
open -a 'Luft' --args --navigate /profile
open 'luft://app/profile'

# Android: cold/warm launch through an explicit intent, with no domain registration.
adb shell am start -n dev.tuist.guild/.MainActivity --es navigate /profile
adb shell am start -a android.intent.action.VIEW -d 'luft://app/threads/12345678-1234-5678-9abc-123456789abc' dev.tuist.guild

# GPUI: arguments also forward to an already-running window.
Luft --list-routes
Luft --navigate /profile
```

Apple consumes `--navigate` at startup; terminate the existing process before testing another launch argument. Use OS URL delivery for an already-running Apple app. Android consumes intent data/extras once, including across Activity recreation. No launch mechanism bypasses authentication.

### Push notifications

When a thread stops working (it replied, failed or was interrupted), the Tuist upstream notifies its owner's Luft devices, never the Tuist app's (`Tuist.Push.Workers.ThreadFinishedWorker`). The alert shows a fixed status line and, once the agent has named the thread, its title; until then a thread is titled with the start of its first message, so the alert says "Your thread" instead and never shows message content. It carries `url` (`https://<Luft server>/luft/threads/{id}`), `account` (the handle of the account that owns the thread) and `user` (the handle of its owner, since threads are visible only to them). Registrations go through the Luft proxy using its scoped Tuist grant and record their app as `luft`, separate from the shipping app's `tuist` registrations.

As in the Tuist app, notifications are off until the person turns on **Notifications on This Device** in Profile, which records the choice for the active profile in the core (`push_enable`). Turning it on asks for notification permission; iOS and macOS then register with APNs and pass the token to the core's `push_register`, which registers it for the active profile at `/api/me/push-devices/{installation}`. Turning it off unregisters, and stays on if the server can't be told. A device token reaches one sign-in at a time, so switching to a profile with notifications on moves it there, and returning to the foreground refreshes it. Removing the device from the device list turns the switch off. Signing out unregisters; when the server can't be told, for example offline, the app also invalidates its APNs token, as the Tuist app does, because signing out doesn't end the server's grant, and doesn't register again until the next launch or until the switch is turned on, since APNs may return the same token. A tap calls `open_notification`, which switches to the owner's saved profile and the account the notification belongs to and opens the thread; a tap that launches the app waits for the core to boot, and a notification for the conversation on screen shows no banner.

A build only offers the switch when Info.plist's `LuftPushEnvironment` names an APNs environment: the simulator build says `sandbox`, and `ios/distribution/bundle.sh` stamps the device IPA from the provisioning profile's `aps-environment`, which needs Push Notifications enabled on the `dev.tuist.code` App ID and a regenerated **Tuist Code Ad Hoc** profile. The Developer ID macOS copy has no provisioning profile yet, so it doesn't register. Android does not receive notifications yet, and the server refuses Luft Android registrations: every app shares the server's one FCM project, so Luft needs its own Firebase project and SDK packaging first. The server's APNs key must not be restricted to the Tuist app's topic.

### Threads Live Activity

On iOS, while threads are working, the app starts one Live Activity in the foreground (`apple/Sources/ThreadLiveActivity.swift`) and passes its push token to the core's `live_activity_register`. From then on the server pushes the activity's whole content (`Tuist.Push.LiveActivities`): a versioned document with a summary and up to three threads, each with its title, a phase picked from the running tool's name, progress and a link back into the app. The extension in `ios/LiveActivity/` only draws that document and has no network or credentials. The server ends the activity once nothing is working. Device previews sign the extension with its own ad-hoc profile (see [Signed device previews](#signed-device-previews)).

### Legacy desktop links

GPUI additionally retains `tuist://app/profile`, `tuist://app/previews` (which opens Threads) and canonical preview URLs scoped to the selected server. Their frozen shipping-client wire contract is in [navigation.md](../app/navigation.md); native Luft apps do not claim `tuist:`.

A preview link opens an identifier/handoff screen over the current destination,
with Back, Copy link, and Open on web. No preview metadata is requested. Other valid same-server web
pages use the system browser; invalid and wrong-server links leave the current
destination intact and show a dismissible error.

For explicit **development/portable installation** on Linux, run
`bash distribution/install-linux.sh /absolute/path/to/Luft`. On Windows, run
`powershell -File distribution/install-windows.ps1 -Binary C:\path\to\Luft.exe`.
These install per-user and make this app the `luft:` and legacy `tuist:` handlers, replacing any
existing association for those schemes. They do not claim HTTP/HTTPS. Do not register the development
macOS binary over the shipping Swift app. These scripts are not an auto-updater
or the production installer; quit the app before reinstalling.

## Theme

Every client uses Noora's semantic light/dark tokens from `../noora/css/tokens.css`,
the same tokens as the server. `crates/core/noora_tokens.py` converts the base
OKLCH colors (not the CSS Display P3 overrides) to sRGB and writes
`crates/core/src/theme/noora.rs`; rerun it after Noora changes, and
`mise run test` fails when the generated file is stale. The core exposes the
table to Apple (`tuist_app_theme`) and Android (`AppCore.theme`), and GPUI reads
it directly.

Profile offers a theme choice on every client: **Tuist** (Noora's tokens), which
follows the OS light/dark appearance, then [Omarchy](https://omarchy.org)'s built-in themes
(Tokyo Night, Catppuccin, Gruvbox, Rose Pine and the rest), which carry their own
appearance. The core maps each Omarchy `colors.toml` palette onto Noora's tokens,
so edges draw only with token names and every theme restyles every client the
same way. `crates/core/omarchy_themes.py <omarchy checkout>` vendors the palettes
into `crates/core/src/theme/omarchy_themes.rs`; rerun it to pick up new upstream
themes. The choice stays on the device: `UserDefaults` on Apple, private
`SharedPreferences` on Android, and `desktop/settings.json` beside the saved
accounts on GPUI. The UI never names Noora or Omarchy: users see Tuist, Desktop
and each theme's own name.

On Linux, GPUI also offers **Desktop**, which follows the desktop's current
Omarchy theme, and uses it by default until someone picks another theme. Read
`~/.local/state/omarchy/current/theme/colors.toml`, falling back to the pre-v4
`~/.config/omarchy/current/theme/colors.toml` path only if the modern directory
does not exist. Respect `mode`, legacy `theme_type`, `light.mode`, and Omarchy's
background-brightness detection in that order. Keys resolve through the same
alias and fallback cascade as `omarchy-theme-color`, Omarchy's shared resolver. Accent button labels use the higher
contrast black/white foreground rather than assuming white works for every theme.
Dim text colors below 4.5:1 against the content background use the palette's
normal foreground instead, keeping identifiers readable without inventing a color.

The background loader rereads the paths every second so directory/symlink
replacement during theme switches works without restarting Tuist. No theme
scripts run, and no file reads happen while rendering. Missing or malformed
palettes fall back entirely to Noora (or the chosen theme), rather than
mixing a corrupt palette with defaults or reviving a stale legacy theme.

## Packaging and updates

Linux releases use AppImage; Windows releases use a per-user NSIS installer.
Both register `luft:` and the legacy `tuist:` scheme, never HTTP/HTTPS. The existing Swift macOS app and its
Sparkle release process remain unchanged.

Packaged installations check for updates at launch. **Check for updates…** in
the bottom bar also checks manually, including while signed out. A newer release
shows its version and notes and asks for **Install update and restart**. The
app authenticates the manifest and payload before installation, quits the event
loop, and releases its single-instance lock before installing and restarting.
Updates do not change the account/credential directories.

Development builds have no verification key and cannot update themselves.
Portable binaries and package-managed Linux installs must be updated manually or
through their package manager; the updater only supports the packaged AppImage
runtime and the per-user NSIS installation. No update is installed just because
a link was opened.

See [distribution/README.md](distribution/README.md) for packaging commands,
release/signing setup, platform gates, and first-release requirements. Adding the
workflow does not provision signing keys or publish a release.
