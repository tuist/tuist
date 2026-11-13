# Tuist app — parallel client

An alternative client developed alongside the shipping apps, not a replacement or a store release. Its independent Once graph reports to [tuist/app](https://tuist.dev/tuist/app). The Rust workspace moved here from `desktop/`; GPUI remains the Linux/Windows UI, SwiftUI provides iOS/macOS interfaces, and Kotlin provides the Android interface. Native profiles, OAuth, session selection, and preview API operations are implemented in `crates/core`, reusing the existing Rust OAuth/PKCE and JWT logic.

The shipping Swift `Project.swift`, `Sources/`, `Resources/`, and `Tests/` stay in place. The shipping Android Gradle app stays in `../android/`. New native apps use bundle/package ID `dev.tuist.app.preview`, display as **Tuist Preview**, and register only `tuist-preview://oauth-callback`, not the shipping `tuist:` scheme, associated domains, push capabilities or updater feeds. They do not read or modify shipping-client credentials. The GPUI client retains its existing credential interoperability and desktop identity.

## Build the parallel client

Run from this directory. Exclude the root mise configuration only for these commands so the CLI toolchain/bootstrap is not installed for the new client:

```sh
export MISE_IGNORED_CONFIG_PATHS="$(git rev-parse --show-toplevel)/mise.toml"
mise trust
mise install
once auth login --provider tuist
mise run test:core
mise run build:ios
mise run build:ios-device
mise run build:macos
mise run build:android
mise run build
mise run test
```

These commands upload build/test insights and use the hosted `tuist/app` cache. Set `ONCE_CACHE_PROVIDER=local` for credential-free offline builds instead. Cache reuse requires the same platform, toolchain, and build inputs; warm local outputs alone do not demonstrate remote reuse.

Apple builds require Apple Silicon macOS/Xcode and `rustup target add aarch64-apple-ios-sim aarch64-apple-ios`. Android needs Java 17+, Kotlin, compile SDK 36 (target SDK remains 35), build-tools 35.0.0, `ANDROID_HOME`, `ANDROID_NDK_HOME`, `rustup target add aarch64-linux-android`, and a local debug keystore. Once resolves the NDK linker from `ANDROID_NDK_HOME`. Python 3.11+ is required for preparation. Build products live under `.once/out/<target>/`: `TuistAppIOS`, `TuistAppIOSDevice`, `TuistAppMacOS`, and `TuistAppAndroid`. The iOS device output is ad-hoc signed and cannot install on hardware until separately provisioned/re-signed, including the appropriate application identity/Keychain entitlements; this change provisions no signing identities. Simulator-only entitlements give its separate preview sandbox Keychain access.

Swift imports the core's C module, Kotlin calls its JNI bridge, and the existing Rust navigation crate re-exports the same `Tab` type. GPUI and its dependency graph are not in the native frontend build closures. Platform code supplies localized presentation, browser callbacks, secure storage and ordinary platform-trusted HTTPS; Rust owns authentication, refresh and authorized API operations, without its own mobile HTTP/TLS stack. See [the bridge contract](crates/core/README.md).

Mise runs `prepare-native.py` before graph loading. When invoking Once directly, run `python3 prepare-native.py` first. This derives an ignored metadata-only Cargo workspace and vendors its dependencies, avoiding desktop feature unification and generated-target collisions in Once 0.77.5. Every external version/source/checksum must match the authoritative `Cargo.lock`; first-party compilation always uses the original `crates/` sources, never the metadata stubs. Preparation may download missing crates. For Android, additionally run `python3 android/dependencies.py prepare`; its checksum-locked AndroidX Browser closure and final-APK resource verification are documented in [Android dependencies](android/DEPENDENCIES.md).

## Native profiles, authentication and sessions

Both mobile interfaces support saved profiles, per-profile organizations, hosted/self-hosted sign-in, sign-out and confirmed account deletion. Previews include project selection, full-project track counts, server-side debounced search, pagination, detail metadata and full plain-text release notes. iOS offers confirmed IPA installation; Android offers a confirmed HTTPS APK handoff. Authentication uses an ephemeral system browser, exact single-use callback/state validation, public dynamic client registration and PKCE. Android requires an ephemeral-capable Custom Tabs provider and fails closed when none is available.

Session storage follows the existing platform boundaries, but not the shipping app's sandbox:

- **iOS/macOS:** Keychain generic-password service `dev.tuist.app.preview.profiles`, account `profiles-v1`, non-synchronizing `AfterFirstUnlockThisDeviceOnly`. No desktop session files are used.
- **Android:** private `shared_prefs/tuist_secure_prefs.xml`, key `vault`, containing one AES-GCM encrypted record. The encryption key stays in Android Keystore under `tuist_preview_vault`; backup and device transfer are disabled. The application sandbox locates the preferences file, never a hard-coded `/data` path.

Rust treats the vault as private, never sends credentials in view snapshots, binds refreshes to the issuing origin/client, persists selection before publication, and retains rotated credentials in memory until a failed durable write can be retried. An interrupted process cannot preserve a memory-only rotation. Profile/organization changes discard stale native navigation and API results. There is no credential migration or sharing with current clients.

CI authenticates trusted builds through GitHub OIDC for hosted caches and insights; forks use local caches without login. The isolated optimized Linux/Windows packaging step still uses a local cache. CI retains unsigned/unprovisioned workflow artifacts. There are no store uploads, public release jobs or enabled new-client updater keys. The private hosted project is linked to `tuist/tuist`.

## Internal previews

After building, explicitly publish the simulator, native macOS or Android APK with `mise run preview:ios`, `mise run preview:macos`, or `mise run preview:android`. Each publishes to the private project's `internal` track. Builds and tests do not automatically publish previews. The **App next** workflow (`.github/workflows/app-next.yml`) can also publish these three artifacts when manually dispatched on `main` with `publish_previews` enabled; publication is off by default and never runs on pull requests. The existing shipping-client build workflow remains **App** (`app.yml`). The device bundle is deliberately excluded until internal signing is configured. macOS is ad-hoc signed, not notarized; Android uses a development debug key, not a stable distribution identity, so previews from different machines may require uninstalling the previous debug app.

Linux executables built through Once can be published with the Tuist CLI's `share` command using an isolated `tuist.toml` containing `project = "tuist/app"` and `--track internal`. Do not invoke `share` against the legacy `Tuist.swift`, which belongs to the shipping client. Once's Rust binary target does not yet export native artifact metadata, so the native `once artifact publish` tasks do not cover GPUI. Windows packaging remains in CI; neither a local MSVC build nor hosted Windows preview publication has been verified. The server currently projects executable previews only for Linux and macOS.

For legacy Swift commands run from this directory, exclude the parallel toolchain instead: `MISE_IGNORED_CONFIG_PATHS="$PWD/mise.toml" mise exec -- tuist generate --no-open`.

## Preview icons and names

Native Apple/Android bundles declare **Tuist Preview** as their display name and retain the isolated `dev.tuist.app.preview` identity. Their icons are rendered from the shipping `Resources/TuistApp/AppIcon.icon`; regenerate the checked-in raster/ICNS resources on a Mac with Xcode 26+ using `bash apple/generate-icons.sh`. Shipping resources are read-only inputs. Explicit PNG/ICNS resources keep icons in Once's cached outputs, including the iOS fallback icons.

Hosted metadata currently has limitations: Once 0.77.5 omits the Android display label and preview icon payloads, and the server projects Android names from the application ID. Raw Linux executable previews are labeled CLI regardless of whether they open a GUI. Bundle icons do not repair existing hosted previews; metadata publication and a fresh upload are needed.

## GPUI frontend

Build the Linux/Windows frontend through Once with `mise run build`, then launch with `mise run run`. macOS remains a GPUI development host; the native Swift macOS target is the new Apple frontend. This is an early shell, not a replacement for the shipping Swift app's preview browsing or installation features.

The GPUI source layout uses Once's `build_script_sources` support, included in
the pinned [Once 0.77.5 release](https://github.com/tuist/once/releases/tag/0.77.5).
This release also aligns build-script debug assertions with optimized crates,
which GPUI needs to generate shaders for Windows packaging.
Run `mise install` to install the published toolchain before building.

## Servers and accounts

Open the avatar at the top right of the application title bar to switch directly
between saved profiles, view your profile, sign out, or open app settings. The
menu shows the server alongside each account and marks the current profile.
Use **Add account or server…** (also available as **Accounts and servers…** on
the welcome screen). Enter `https://tuist.dev` or an HTTPS self-hosted
server URL, then complete browser sign-in. Multiple logins on the same server
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
Saved accounts remain reachable through **Accounts and servers…** on sign-in.

## Keyboard access and accessibility

Tab and Shift-Tab move through enabled controls in visual order, with a visible
focus border. Enter or Space activates a focused button; focusing an off-screen
control scrolls it into view. This covers sign-in providers, account/server entry,
workspace navigation, preview actions, settings, sign-out, error dismissal and
manual update checks. Text entry retains its normal editing and clipboard keys;
Enter submits the server form. Escape cancels browser sign-in or closes the account
form/settings. These screens are pages, not modal dialogs.

The account menu uses arrows and Home/End, Enter/Space activation, Escape to
restore the opener, and Tab/Shift-Tab to close and leave the menu. Application
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

The last selected server survives restarts. An explicit `TUIST_URL` overrides
that startup selection, but startup fails closed if another full server URL
owns the same host's canonical credentials. Switching accounts clears preview/detail navigation
and pending links rather than delivering a previous account's route to the new
session. Signing out removes the selected account, not every saved login.

The active credentials keep the Swift app/CLI file format and host-only identity:
`<config>/credentials/<normalized-host>.json`. Selecting another login on that
host changes the shared active credentials too. CLI/macOS changes are detected
when this window regains focus. Rotation and switching use the shared refresh
lock; the latest canonical tokens win over an older desktop snapshot.

| Platform | Active credentials | Additional desktop accounts |
| --- | --- | --- |
| macOS development | `~/.config/tuist/credentials/` | `~/.config/tuist/desktop/accounts.json` |
| Linux | `~/.config/tuist/credentials/` (CLI compatibility) | `$XDG_DATA_HOME/tuist/desktop/accounts.json`, default `~/.local/share/tuist/desktop/accounts.json` |
| Windows | `%LOCALAPPDATA%/tuist/credentials/` | `%LOCALAPPDATA%/tuist/desktop/accounts.json` |

macOS honors `TUIST_XDG_CONFIG_HOME`/`XDG_CONFIG_HOME` for both locations.
Desktop account data honors `TUIST_XDG_DATA_HOME`/`XDG_DATA_HOME` on Linux and
Windows. Locks honor the corresponding state-home variables, with macOS/Linux
defaulting to `~/.local/state/tuist`, and Windows to `%LOCALAPPDATA%/tuist`.
Only absolute overrides apply, and `TUIST_` takes precedence over plain XDG.
Windows credentials are local, never placed in roaming `%APPDATA%` by default.

Saved account files contain access and refresh tokens, like the shared CLI
file. They are atomically replaced and private (`0600` on Unix; Windows inherits
the user's local application-data directory permissions). They are not
encrypted by an OS credential vault. Do not sync, share, or commit these files.
The shared Swift/CLI credential contract distinguishes hosts, not ports or URL
base paths. The desktop registry tracks which full server URL owns each host's
active file, so switching through another host cannot overwrite an inactive
deployment's saved login. Older registries infer ownership only from a sole
profile or an unambiguous exact credential match; otherwise snapshots stay intact
until explicit sign-in or account selection establishes ownership. Out-of-band
CLI sign-in to a different deployment on the same host remains indistinguishable
because the shared file contains no full issuer URL.

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

The app accepts `tuist://app/profile`, `tuist://app/previews`, and canonical
preview URLs scoped to the selected server (production by default). The shared wire
contract and mobile examples are in [navigation.md](../app/navigation.md).
URLs passed as arguments or delivered by the OS reach the existing window.
Links received while signed out wait for sign-in; navigation never signs in,
changes servers, installs, or runs a preview.

A preview link currently opens an identifier/handoff screen with Back, Copy link,
and Open on web. No preview metadata is requested. Other valid same-server web
pages use the system browser; invalid and wrong-server links leave the current
destination intact and show a dismissible error.

For explicit **development/portable installation** on Linux, run
`bash distribution/install-linux.sh /absolute/path/to/Tuist`. On Windows, run
`powershell -File distribution/install-windows.ps1 -Binary C:\path\to\Tuist.exe`.
These install per-user and make this app the `tuist:` handler, replacing any
existing association. They do not claim HTTP/HTTPS. Do not register the development
macOS binary over the shipping Swift app. These scripts are not an auto-updater
or the production installer; quit the app before reinstalling.

## Theme

Noora's semantic light/dark tokens in `../noora/css/tokens.css` are the default.
The desktop mapping uses the base OKLCH colors converted to sRGB, not the CSS
Display P3 overrides. The OS window appearance selects light or dark.

On Linux, Omarchy takes precedence when present. Read
`~/.local/state/omarchy/current/theme/colors.toml`, falling back to the pre-v4
`~/.config/omarchy/current/theme/colors.toml` path only if the modern directory
does not exist. Respect `mode`, legacy `theme_type`, `light.mode`, and Omarchy's
background-brightness detection in that order. Semantic and legacy ANSI palette
keys map to the desktop's semantic roles. Accent button labels use the higher
contrast black/white foreground rather than assuming white works for every theme.
Dim text colors below 4.5:1 against the content background use the palette's
normal foreground instead, keeping identifiers readable without inventing a color.

The background loader rereads the paths every second so directory/symlink
replacement during theme switches works without restarting Tuist. No theme
scripts run, and no file reads happen while rendering. Missing or malformed
palettes fall back entirely to Noora and the current OS appearance, rather than
mixing a corrupt palette with defaults or reviving a stale legacy theme.

## Packaging and updates

Linux releases use AppImage; Windows releases use a per-user NSIS installer.
Both register only the `tuist:` scheme. The existing Swift macOS app and its
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
