# Tuist desktop app

Rust and [gpui](https://crates.io/crates/gpui) desktop app for Linux and Windows,
built with Once. It also compiles on macOS so changes can be tried locally; the
Swift app in `app/` remains the shipping macOS client. This is an independent
Once workspace: Cargo owns the dependency graph and `once.toml` seeds it with a
single `cargo_workspace` target. Builds report to the Tuist project
`tuist/desktop-app` (the `desktop` handle is reserved) for caching and insights;
sign in once per machine with `once auth login --provider tuist`.

The app signs in with the browser and shows a Previews/Profile shell; Previews
has no server data yet.

## Crates

Keep the workspace horizontal: small crates with explicit dependencies, so
Once compiles, tests, and caches each one independently and an edit rebuilds
only its dependants. Only `app` depends on gpui; never pull UI or gpui types
into the library crates.

- `crates/jwt`: unverified JWT claim reading (expiry, type, account).
- `crates/credentials`: the credential files and refresh lock shared with the
  CLI and the Swift app.
- `crates/oauth`: blocking calls to the server's OAuth endpoints, PKCE, and the
  loopback redirect listener.
- `crates/session`: composes the three into status, access tokens, sign-in,
  sign-out, and saved-account selection. Its `AuthorizationServer` trait lets
  tests fake the server.
- `crates/navigation`: validates the shared mobile URL contract and owns pending
  delivery and tab/detail state, without depending on gpui.
- `crates/updater`: authenticates update metadata and payloads, without gpui.
  Checks/downloads run off the UI thread. Install only after user approval,
  event-loop shutdown, and dropping the single-instance owner. Release packaging
  and signing are documented in `distribution/README.md`.
- `app`: gpui views. `LogIn` owns a sign-in in progress; `Root` switches screens,
  receives links and gates navigation on sign-in, and `Workspace`
  binds that same navigation state. Run session calls on the background executor,
  never the UI thread.

Add a crate when a real dependency boundary appears (a new server API, a
feature with its own state), not for every module.

## Shared session

Sign-in must interoperate with `tuist auth login` and the macOS app, which read
the same files. Treat these as a frozen contract with
`cli/Sources/TuistServer/Utilities/ServerCredentialsStore.swift`,
`ServerAuthenticationController.swift`, and `CachedValueStore.swift`:

- Credentials live in `<config>/credentials/<lowercased host, trailing dots
  removed>.json` as Swift's `ServerCredentials` JSON (`accessToken`,
  `refreshToken`, `oauthClientID`, `rejected`). Read legacy host aliases; sign
  out deletes all of them. Corrupt files are errors, never "signed out".
- `<config>`/`<state>` follow `Environment.configDirectory`/`stateDirectory`
  on macOS (`TUIST_`-prefixed then plain XDG variables). The Linux CLI keeps
  credentials under `$HOME/.config/tuist`. Windows has no Swift client and uses
  non-roaming `%LOCALAPPDATA%` for credentials, desktop account data, and locks.
- Rotation holds an exclusive file lock at
  `<state>/cached_value_store/credential-refresh-<unpadded FNV-1a 64 hex of the
  credentials path>.lock`, rereads the store under the lock, keeps a peer's
  newer pair over a replayed response, and marks credentials `rejected` only
  when nobody rotated them meanwhile. Transient failures keep credentials.
- Browser sign-in registers a public PKCE client for a `127.0.0.1` loopback
  redirect (RFC 8252) through the server's same-origin registration endpoint,
  and stores the issuing client ID so every client refreshes with it. Account
  refresh tokens use `/oauth2/token`; legacy CLI tokens use
  `/api/auth/refresh_token`.
- `Accounts` owns additional login snapshots and the selected full server URL,
  separate from the frozen canonical file. Use it for desktop sign-in,
  switching, and sign-out; never restore archived tokens over a fresher shared
  pair. Account operations lock the registry before sorted host refresh locks.
  Workspace sessions bind their identity and full server profile. Credential use
  holds the registry lock before the host lock through refresh and its writes,
  so old work cannot use another profile's login even with the same account ID.
- The account/server form accepts HTTPS URLs. `TUIST_URL` overrides the saved
  startup selection; internal development resolution also allows HTTP loopback.
  See `README.md` for platform storage paths and the browser account contract.

## UI references

- Use the [Zed codebase](https://github.com/zed-industries/zed) as the reference
  for gpui usage, desktop UI, and UI patterns: `crates/gpui` (framework and
  examples), `crates/ui` (components), and `crates/workspace` and
  `crates/title_bar` (app shell, panes, and window chrome).
- Use the [gpui-component](https://github.com/longbridge/gpui-component)
  components directory (`crates/ui/src`) as the reference for ready-made
  components such as lists, inputs, tables, and sidebars.
- GPUI and `gpui_platform` are pinned together to an AccessKit-capable Zed git
  revision in `Cargo.toml`. Check APIs against that exact checkout, not the
  published 0.2.2 crate, which lacks accessibility support. Upgrade deliberately.
- Follow the platform conventions those projects implement: keyboard shortcuts
  use `cmd` on macOS and `ctrl` elsewhere, and the window follows the system
  light/dark appearance. Use Noora semantic tokens, with the active Omarchy
  palette taking precedence on Linux. See `README.md` for source paths and
  background reloading; never read files during rendering or execute theme scripts.

## Accessibility and keyboard navigation

Accessibility is a requirement, not optional polish. Every actionable control
must be reachable and operable without a pointer, including signed-out flows,
errors, account switching, settings, and updates. Use the shared keyboard-control
behavior, logical visual Tab/Shift-Tab order, visible focus, and scroll focused
controls into view. Disabled controls must not activate or remain in Tab order.
Keep normal text-editing keys intact. GPUI already generates button clicks on
unmodified Enter/Space key-up; do not add duplicate key-down activation.

Follow the [APG keyboard patterns](https://www.w3.org/WAI/ARIA/apg/patterns/)
and native desktop conventions: arrows/Home/End within menus, Escape to dismiss
transient UI and restore focus, Tab to close and leave a menu. Move focus to a
logical visible control when a screen or focused control disappears. A full-page
form is not a modal; a future modal must isolate background controls and contain
Tab navigation. Verify real keyboard flows, focus restoration and compact-window
scrolling, not only command-handler calls.

Expose stable IDs and semantic roles/names on controls through GPUI's AccessKit
bridge. Keep state, editable text/selection and live announcements synchronized.
Hide covered background subtrees separately from keyboard focus management.
Use accessible text elements for standalone text; plain strings and tooltips
are not accessible names. GPUI's test platform does not activate the native
adapter: node/listener tests do not establish OS screen-reader compatibility.
Record native VoiceOver/Narrator/NVDA/Orca acceptance separately in the README.

## Brand assets

- Brand assets live in `app/resources/`. `img()` treats a path that parses as
  a URI (a bare `name.png` is a valid host) as a network URL, so keep embedded
  image paths inside a directory.
- `resources/icon.png` is the app icon, the 256px flat export of
  `app/Resources/TuistApp/AppIcon.icon`; refresh it when that icon changes. It
  is the Dock icon on macOS, set at launch because the binary is unbundled.
- `resources/tuist-mark.svg` is the web dashboard's five-petal mark
  (`tuist_mark` in `server/lib/tuist_web/components/icon_components.ex`). In-app
  branding uses it, tinted with the theme accent, not the app icon.
- The binary is named `Tuist` because unbundled macOS apps show the executable
  name in the Dock.

## Commands

Run from this directory:

The GPUI source layout in `once.toml` requires Once's `build_script_sources`
support; optimized Windows builds also require its build-script debug-assertions
fix, and Windows staged builds need its Cargo workspace path comparison fix,
its non-verbatim command path fix, and `SystemRoot` in Rust test environments.
All are available in the pinned 0.77.5 release. Use the published binary
installed by mise. Do not replace this dependency with patched Cargo sources.

```sh
mise install
ONCE_CACHE_PROVIDER=local mise run build
ONCE_CACHE_PROVIDER=local mise run run
ONCE_CACHE_PROVIDER=local mise run test
ONCE_CACHE_PROVIDER=local mise run check
```

`once query targets --kind rust_binary` lists the generated binary target that
`mise run run` launches. Linux builds need the X11/Wayland, xkbcommon, Vulkan,
fontconfig, and freetype development packages that Zed's `script/linux` installs.
Windows builds need the MSVC toolchain and Windows SDK. macOS builds use
gpui's `runtime_shaders` feature so the Metal toolchain is not required.

## Constraints

- Development builds keep the updater public key and package-kind files empty.
  Release staging stamps them before Once builds; keep them declared source
  inputs. Never embed a private key or use PR-writable caches for signed releases.
- Keep the Cargo package standalone (its own `[workspace]`), so the monorepo's
  other Cargo projects are never resolved here.
- Do not switch to building with plain Cargo to work around Once failures; fix
  the Once graph instead.
