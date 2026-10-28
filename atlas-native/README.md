# Atlas native

Native clients for Atlas, with a shared Rust core and builds powered by
[Once](https://github.com/tuist/once).

| Layer | Technology |
| --- | --- |
| Shared core | Rust, exposed through a C ABI and JNI |
| Command line | Rust, using the shared core directly |
| Android | Kotlin and native Android widgets |
| iOS | Swift and SwiftUI |
| macOS | Shared SwiftUI features with a native desktop shell and Sparkle |
| Build, test and cache | Once |
| Internal distribution | [tuist/atlas-mobile](https://tuist.dev/tuist/atlas-mobile) |

The app signs in to hosted or self-hosted Atlas using its existing browser login
page, then presents a native workspace using the shared Rust catalog.
Rust owns OAuth discovery, dynamic public-client registration, S256 PKCE, token
exchange and refresh. iOS and macOS present a system authentication session and store
credentials in Keychain; Android opens the system browser and encrypts credentials
with an Android Keystore key. Saved sessions are restored on launch. Self-hosted
servers require HTTPS and OAuth discovery/dynamic registration support.

The native login screens follow Tuist's welcome layout, backdrop, spacing,
button treatments and rounded bottom panel, customized with Atlas's azure palette
and the same Tuist mark used by Atlas's web login and dashboard. They offer Atlas-hosted and self-hosted browser sign-in; provider
selection happens on the server's login page. Light and dark assets share a
checked-in generator under `resources/`.

Tasks, sales accounts, manual invoice bookkeeping, employee time off, People and
Profile use native screens and authenticated APIs. Browse displays implemented
native destinations only; the shared catalog/CLI also retain browser routes.
Native OAuth tokens do not create browser cookies. The app is not a WebView
wrapper and does not provide offline editing.

## Personal account connections

Profile → Connections manages personal GitHub, Slack and Google grants separately
from AI accounts and Atlas sign-in. Connect/Reconnect opens the server's consent
flow in the system browser; disconnect requires confirmation. The Atlas browser
login must belong to the same person as the signed-in native session.

The bearer-authenticated `/api/me/connections` API exposes only connection metadata
and disconnect. Its native-only authorization endpoint issues a ten-minute signed
browser handoff bound to the user, provider, native client and random state.
Providers continue using the server's HTTPS OAuth callbacks. After consent Atlas
returns to `dev.tuist.atlas://connections-callback` with only state, provider and
status, never a provider token. This is separate from `oauth-callback` for Atlas
sign-in. Rust validates the exact destination, pending state, selected origin,
issuing client and expiration; both apps reload authenticated metadata afterward.
Android encrypts pending handoffs so browser returns survive process recreation.
Sign-out/new login clears pending state, and unrelated drafts block callback navigation.

Provider credentials and API enablement are server configuration, not bundled app
secrets. Older servers show an unavailable-feature explanation without signing the
person out. Preview-only `--connections` (iOS) and `--ez connections true`
(Android Settings preview) render fictional connected/disconnected/reconnect states
without contacting providers or changing accounts.

## Durable read cache

Orbit's first inbox page uses stale-while-revalidate: Rust reads a bounded SQLite
projection before OAuth renewal or HTTP, then replaces it after a protected read.
Returning to the tab retains the in-memory model. Startup and background refresh
show no cache banner. A failed refresh keeps the saved rows and shows a compact
“Couldn’t refresh” with Retry, cleared on recovery. Thread history, attachments,
drafts and live activity are not persisted; opening a saved row still requires a
protected server read.
Other feature lists are not yet backed by this cache.

`auth/src/cache.rs` uses bundled SQLite through `rusqlite` on every platform. The
adapters supply only a private, backup-excluded directory: Application Support's
`Atlas/ReadCache` on iOS (device file protection), or Android's `noBackupFilesDir/reads`.
The database is `reads.sqlite3`. Credentials remain in the existing secure stores,
never SQLite. This is sandbox/file-protected storage, not application-level encrypted
SQLite. Snapshots retain titles, summaries and display metadata, but strip participant
identities, ownership, mutation capabilities and live agent status. Cached rows
cannot authorize mutations.

Keys bind the canonical server origin, a random credential-lifetime namespace,
projection version and kind/status filters. Token rotation retains the namespace;
a new login replaces it. Logout retires it and deletes its rows; generation checks
reject late writes after mutations, revocation or logout. Reads expire after seven
days, with pruning on open, at most 32 snapshots and 1 MiB per snapshot. The default
4 KiB SQLite pages are capped at 4096 pages. Storage failures disable caching without
blocking online use. Remote revocation cannot erase an offline device's already
saved display metadata until it reconnects or the local retention limit is reached.

### SQLite migrations

Append numbered SQL files under `auth/src/cache_migrations/` and append each
`include_str!` to `MIGRATIONS` in `cache.rs`. Never edit a migration shipped in a
release. `PRAGMA user_version` tracks the applied version. All pending migrations
and the version change commit in one immediate transaction; failures roll back
schema and data together. A downgraded app refuses a newer schema without resetting
it and uses the network instead. Change the projection key version when JSON shape
or meaning changes; schema migrations are for actual SQLite layout/data changes.
Keep SQL files in all three production and host-test Once source lists. Tests cover
reopen, data-preserving upgrade, rollback, downgrade, isolation and late-write fences.

## Object navigation

The native clients accept server-bound object links for Orbit, Tasks, Accounts, Finance,
Time off, People and Profile. A link can open a thread, task, account or invoice directly
by UUID, independently of loaded list pages. Notifications, other systems and UI
agents use the same read-only destination contract and normal authentication.
Supported hosted HTTPS links use iOS Universal Links and Android App Links, with
explicit **Open in Atlas** and browser fallback actions on the web. Native screens
also offer **Open in browser** for richer web functionality. Automatic handoff
requires an installed build and verified signing/domain setup; self-hosted
instances use the server-bound custom scheme. macOS registers that custom scheme;
automatic HTTPS association is not enabled for the desktop app.
The shared allowlist in `core/src/destinations.rs` defines seven stable screen keys:
`tasks`, `accounts`, `invoices`, `time-off`, `people`, `profile`, and `orbit`.
Tasks, accounts, invoices, and Orbit accept a record ID. Notifications should carry a `destination_url` using
this grammar, without credentials, titles, API paths, or mutation actions:

```text
dev.tuist.atlas://navigate/<screen>[/<lowercase-uuid>]?server=<encoded-https-origin>
https://atlas.tuist.dev/open/<screen>[/<lowercase-uuid>]
```

Hosted handoff also supports the ordinary pages `/tasks`,
`/commercial/sales/accounts` and its UUID detail, `/people`, `/people/time-off`,
and `/settings`. Matching is exact, not a claim on their descendants. The broader
`/commercial/finance` dashboard stays in the browser; its header can explicitly
open native invoices. Canonical share URLs always use `/open`, while the native
browser escape opens a real web page. Account records have a browser detail;
task and invoice records fall back to their collections. Orbit has no web view,
so its browser fallback is the authenticated dashboard `/`; dashboard URLs are not claimed as Orbit links.

Links never select a server, initiate login, or grant access. A signed-out link
waits for normal sign-in, then must match its HTTPS origin. Pending links are
latest-wins and memory-only, retained across Android rotation but not process
death or session end. Drafts, saves, and AI setup reject navigation with an
explanation; finish or discard the work and reopen the link. Back returns to the
native parent without replacing unrelated feature models.

Queries and fragments on HTTPS links are ignored, never forwarded. Custom-scheme
links require exactly one `server` query parameter. Credentials, encoded paths,
unsupported routes, and noncanonical UUIDs are rejected. Server origins allow
only HTTPS, an ASCII/punycode host, an optional port, and an empty/root path.
Host case and default port 443 are equivalent; other ports must match.

Agents use normal OS ingress on an already authenticated simulator/emulator:

```sh
xcrun simctl openurl booted \
  'https://atlas.tuist.dev/open/tasks/123e4567-e89b-12d3-a456-426614174000'
adb shell am start -W -a android.intent.action.VIEW \
  -d 'dev.tuist.atlas://navigate/accounts?server=https%3A%2F%2Fatlas.tuist.dev%2F' \
  dev.tuist.atlas
```

Installation, verified domain/signing setup, browser context, and user preferences
control OS handoff. Same-domain browsing and typed URLs may stay in the browser;
the explicit web action covers these cases. Custom schemes are not verified and
can be registered by other apps. Fixture navigation tests do not prove live
verification. Operator setup lives in the existing
[deployment guidance](../atlas/deploy/AGENTS.md#native-app-links).

## Orbit Live Activities

iOS shows one aggregate Pip Live Activity on the Lock Screen and Dynamic Island
while the signed-in person's authorized Orbit work runs. The conversation title
leads, with its current phase and elapsed time secondary. Multiple conversations
use a bounded titled list with an overflow count. Titles are cleaned and bounded
to 80 Unicode codepoints; Apple receives them for updates and they can appear on
the Lock Screen. No message excerpts, people or tool output are included. Tapping
reenters the normal origin-bound, authenticated router. A timer is elapsed time,
not percent completion.

The app starts activities in the foreground, reconciles on work changes and every
30 seconds while active, and registers ActivityKit tokens for server APNs updates
after backgrounding. It ends activities on sign-out or no remaining work and marks
missing updates stale. Older servers keep working without this optional feature.
Background delivery requires the existing server APNs configuration and a properly
signed device app; a simulator fixture does not prove remote delivery.

Once builds and embeds a genuine WidgetKit `.appex`. Device distribution also
requires a separate `dev.tuist.atlas.live-activity` ad-hoc profile authorizing the
same certificate and registered devices as the host. See
[distribution guidance](ios/distribution/AGENTS.md). No App Group or extension
access to Atlas credentials is required.

The separate preview app's `--live-activity` mode requests real local activities
with fictional state and no APNs token, network or inference. It provides start,
phase/count update, stale and end controls, reusing the production renderer.

## Develop

Run all commands from `atlas-native/`. It is a separate Once workspace, so the
Atlas server's graph and cache remain unchanged. Build/test tasks materialize
locked third-party Rust sources in `.once/vendor` before Once resolves its
per-crate graph. Run `mise run prepare:rust` first when invoking Once directly.
Navigation/CLI compilation remains independent of authentication dependencies.

```sh
cd atlas-native
mise install rust github:tuist/once
ONCE_CACHE_PROVIDER=local mise run check
```

The toolchain pins Once 0.71.2, Rust 1.96.0, Kotlin 2.4.10 and ktlint 1.7.1.
The preparation workaround is still required: this Once release does not include
[automatic source materialization](https://github.com/tuist/once/pull/390) yet.
Once that fix ships, remove the preparation task, its task dependencies and CI
step, and the three `vendor_dir` attributes together.
SwiftLint uses the monorepo's pinned version. To test changes to
Once itself, invoke the executable built from a local Once checkout in this
workspace in place of `mise exec -- once`.

### Rust CLI

Build the CLI with Once, then run the `atlas` executable directly:

```sh
ONCE_CACHE_PROVIDER=local mise run build:cli
ONCE_CACHE_PROVIDER=local mise run test:cli
.once/out/AtlasCLI/atlas --help
.once/out/AtlasCLI/atlas sections
.once/out/AtlasCLI/atlas url tasks
```

`sections` emits tab-separated IDs, titles and URLs from the shared catalog.
`url tasks` prints `https://atlas.tuist.dev/tasks` followed by a newline, suitable
for shell scripts. Invalid arguments print an actionable error to stderr and
exit with code 2. The CLI does not fetch customer data or store credentials.

The CLI builds for the host, with no mobile SDK required. `once run AtlasCLI --
url tasks` also works, but Once captures the command output in
`.once/out/AtlasCLI/run/stdout.log`. The pipeline builds a Linux CLI archive;
local builds also work on Apple Silicon macOS.

### Android

Install Java 21 and Kotlin, then install the Android SDK packages:

```sh
mise install --locked java kotlin
export ANDROID_HOME=/path/to/android-sdk
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
sdkmanager "platforms;android-35" "build-tools;35.0.0" "ndk;27.3.13750724"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.3.13750724"
mise exec -- rustup target add aarch64-linux-android
```

Once requires a debug keystore to produce an installable APK. It uses
`ANDROID_DEBUG_KEYSTORE` or the standard `~/.android/debug.keystore`. On a fresh
machine without either, create a workspace-local key before building:

```sh
mkdir -p .once
export ANDROID_DEBUG_KEYSTORE="$PWD/.once/debug.keystore"
if [ ! -f "$ANDROID_DEBUG_KEYSTORE" ]; then
  mise exec -- keytool -genkeypair -noprompt \
    -keystore "$ANDROID_DEBUG_KEYSTORE" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi
```

CI generates an ephemeral key in the runner's temporary directory. The password
`android` is the standard public debug-signing password, not a production
credential. Keystores are not committed or uploaded as workflow artifacts.

Build, install and launch the app:

```sh
ONCE_CACHE_PROVIDER=local mise run build:android
adb install -r .once/out/AtlasAndroid/AtlasAndroid.apk
adb shell am start -n dev.tuist.atlas/.MainActivity
```

The APK includes `libatlas_core.so` for `arm64-v8a` and supports Android 8.0+.
Use an arm64 emulator or device. Local/CI builds use a debug key; protected nightly
distribution uses a separately provisioned stable key so Android App Links can
verify the app identity. These are not Play Store release bundles.

### iOS

On Apple Silicon macOS with Xcode and an iOS simulator runtime installed:

```sh
mise exec -- rustup target add aarch64-apple-ios-sim
ONCE_CACHE_PROVIDER=local mise run build:ios
ONCE_CACHE_PROVIDER=local mise run test:ios
xcrun simctl install booted .once/out/AtlasIOS/Atlas.app
xcrun simctl launch booted dev.tuist.atlas
```

The app supports iOS 17+ and links the Rust core statically. `AtlasIOS` builds
for arm64 simulators; `AtlasIOSDevice` builds for physical devices. Neither
build includes the isolated screenshot fixtures.

### macOS

On an Apple silicon Mac with Xcode installed:

```sh
ONCE_CACHE_PROVIDER=local mise run build:macos
ONCE_CACHE_PROVIDER=local mise run test:macos
open .once/macos/Atlas.app
```

`AtlasMacOS` compiles the same SwiftUI feature sources and Rust contracts as iOS,
with a resizable sidebar workspace, compact native business tables, native sheets
and a separate Settings window. Table headers sort loaded rows only; amounts
remain separated by currency, with no invented conversion. Search and filters
still apply on the server before pagination.
It requires macOS 14 or later and currently builds for Apple silicon only. New
record and refresh actions support Command-N and Command-R; the conversation
editor uses Return for a newline and Command-Return to send. Unsaved work blocks
sidebar navigation. Live Activities remain iOS-only. Thread result cards
use their server-provided selectable text fallback on macOS; NSH has no macOS
slice. Voice input requires locally available Apple Speech recognition, never a
cloud fallback.

**Personal tool environments:** Settings has General, AI accounts, This Mac and
Updates tabs. This Mac is off by default and binds an environment to the signed-in
profile on the selected Atlas server. Choose individual folders, immediate
subfolders of project parent directories, or explicitly include Home. File tools
stay inside the selected project. Terminal access is separately opt-in and every
command requires approval of its exact text, Mac and project in the conversation,
on iPhone or Mac. An approved command runs as the macOS user, not in a folder
sandbox, for up to 30 minutes with bounded tail output. Keep-awake is optional
and also applies on battery power. Display tools
are not implemented; their disabled control does not request OS permissions.

Private Orbit conversations select Atlas server or a registered environment and
project from the toolbar. The model loop, Atlas business tools, messages and
encrypted checkpoints remain server-side. Environment selection is frozen when a
run starts. The command ledger survives deployment; a claimed command is never
executed again after an uncertain result. Results can be uploaded idempotently,
and unknown outcomes remain explicit. Closing the Mac app takes its environment
offline without deleting the conversation. Device tools are unavailable to shared
threads, research children and MCP callers. A conversation that has dispatched a
personal tool cannot later be shared. Local paths and consent stay in device-only
Keychain storage scoped to the server and owner; invoked file contents and command
output are sent to Atlas and the configured AI provider.

If a Mac becomes unavailable, cancel any active run and select Atlas server or
another environment for the next message in the same conversation. History stays
on Atlas; local files, installed tools and build artifacts do not move with the
conversation. The environment picker, exact-command review, progress and Stop
action are shared by iPhone and Mac. Terminal jobs wait durably for approval,
then execute independently of the bounded model run. Confirmed completion resumes
the server conversation. A Stop request is not a confirmed stop until the Mac
responds. Keep Atlas open on the execution Mac; a lost or quit Mac leaves an
explicit unknown outcome rather than rerunning the command elsewhere.

The build task prepares an ad-hoc-signed runnable copy in `.once/macos/Atlas.app`.
Once's cached flat bundle is not a distributable macOS app and remains unchanged.
The native icon reuses Atlas's existing white mark and azure artwork, with macOS
rounded-square geometry, padding and shadow. Cargo configuration pins host C/Rust
dependencies to the original Apple silicon macOS 11 floor instead of the selected
SDK's default; the app's SwiftUI deployment minimum remains macOS 14.

**Updates:** the app's **Check for Updates…** command and **Settings → Updates**
controls use Sparkle 2.10.1. Atlas reuses Tuist's Developer ID/notarization and
Sparkle signing references but has its own feed:
`https://github.com/tuist/tuist/releases/download/atlas-appcast/atlas-appcast.xml`.
Trusted main-branch CI gates signing on build/test/lint and credential-free
packaging checks, notarizes and staples before generating the update signature,
then publishes `atlas-macos@<epoch>` before replacing the feed. Set up and protect
the `atlas-macos-releases` GitHub environment with access to the existing
`OP_SERVICE_ACCOUNT_TOKEN` before enabling delivery. The initial feed does not
exist until the first successful release. PR builds never receive signing keys.
Local builds cannot establish notarization or real update installation; validate
a signed old-to-new update separately before distributing widely.

After `build:macos`, verify the publishing tools locally without distribution
credentials or Keychain changes:

```sh
bash macos/distribution/test-packaging.sh
bash macos/distribution/test-framework-boundary.sh .once/out/AtlasSparkle/sdk/Sparkle.framework
bash macos/distribution/test-appcast.sh .once/out/AtlasSparkle/sdk .once/macos/Atlas.app
```

The appcast check generates two successive updates with disposable keys, verifies
their archive signatures with Sparkle and CryptoKit, and checks tamper rejection,
build monotonicity and feed history. macOS CI runs these real-tool checks before
uploading the unsigned app; notarization/provider operations use separate fixtures
locally and remain unproven until an authorized release.

**Notifications:** Profile offers opt-in native macOS alerts when the server
advertises desktop push support. Notification clicks reopen the workspace and use
the existing origin-bound navigation; signing out disables enrollment and retries
offline server cleanup on the same origin. Already accepted Apple alerts can
still arrive after sign-out. Foreground views suppress banners while editing.

Desktop releases additionally require a Push-enabled **Developer ID** profile for
the explicit Mac App ID `dev.tuist.atlas.macos`, stored at
`op://tuist/Atlas macOS Developer ID/Atlas_macOS_Developer_ID.provisionprofile`.
Create/regenerate it under team `U6LC622NKF` for the existing Tuist Developer ID
Application certificate and grant the protected release account read access.
Packaging verifies the profile and derives the macOS APNs entitlement/environment;
an iOS profile is not interchangeable. Local ad-hoc builds intentionally have no
push entitlement or environment stamp. The server separately requires
`ATLAS_APNS_MACOS_ENABLED=true` and APNs credentials authorized for the fixed
desktop topic `dev.tuist.atlas.macos`. Older servers omit that capability safely.
See [desktop distribution](macos/distribution/AGENTS.md) and
[server push setup](../atlas/deploy/AGENTS.md#push-notifications) for rollout
and signed-app delivery checks. Builds do not create the profile or configure Apple.

`AtlasMacOSPreview` is an optional offline workspace using fictional fixtures;
it is never part of release builds. See [preview guidance](previews/AGENTS.md).

### Signed device previews

Device previews use ad-hoc distribution, not TestFlight. We can reuse the
**Apple Distribution** certificate used by the Tuist app; no new certificate is
needed while it remains valid. Provisioning profiles are app-specific, so the
Tuist app's existing profile cannot sign Atlas.

One-time setup in Apple Developer (Tuist GmbH, team `U6LC622NKF`):

1. Register the explicit app identifier `dev.tuist.atlas` and enable its
   **Associated Domains**, **Push Notifications**, and **App Groups** capabilities.
   Register `dev.tuist.atlas.share` with **App Groups**, and assign
   `group.dev.tuist.atlas.share` to both identifiers before generating profiles.
2. Register each team iPhone/iPad's UDID (or select the devices already registered
   for the Tuist app).
3. Create **Ad Hoc** profiles named **Atlas App Ad Hoc** and **Atlas Share Ad Hoc**
   for their respective identifiers, selecting the same existing distribution
   certificate and devices.
4. Store the profiles as documents in the `tuist` 1Password vault, named
   `Atlas_App_Ad_Hoc.mobileprovision` and `Atlas_Share_Ad_Hoc.mobileprovision`.
   `ios/distribution/bundle.sh` references these documents by item ID. Update its
   references and packaging fixtures when creating replacement items.
5. Ensure the GitHub `OP_SERVICE_ACCOUNT_TOKEN` can read both items and the
   existing `Distribution Certificate` item (`distribution.p12` and `password`).
   Keep access limited to the protected `atlas-mobile-previews` environment.

Never revoke or replace the Tuist app's certificate just to add Atlas. Regenerate
the host, Share, and Live Activity profiles together when adding devices or
renewing their certificate/profiles, and replace the stored documents. A device
not included in every profile cannot install the IPA, even if it can access the
private preview page.

Build and package locally on macOS with Xcode and authorized 1Password access:

```sh
mise exec -- rustup target add aarch64-apple-ios
ONCE_CACHE_PROVIDER=local mise run build:ios-device
mise run bundle:ios
mise exec -- tuist share delivery/ios-device/Atlas.ipa --track nightly
```

Once 0.68.2 builds ad-hoc-signed device bundles but cannot apply distribution
identities/profiles. `ios/distribution/bundle.sh` therefore copies the built app,
validates the app-specific profile and matching certificate, embeds the profile,
derives device/Keychain entitlements from it, signs in a disposable keychain and
packages `delivery/ios-device/Atlas.ipa`. It never mutates cached build outputs or
imports the private key into the login keychain. The disposable keychain is added
to the user search list while signing, then the original list is restored on exit;
`codesign --keychain` alone is insufficient for certificate-chain lookup. Signing
inputs stay outside the repository and caches. The IPA embeds the provisioning profile, as required by
iOS, but never the certificate's private key. Only the trusted main-branch
publication job receives 1Password access; PR and fork builds compile the same
device target without distribution secrets.

Open the private [Atlas previews](https://tuist.dev/tuist/atlas-mobile/previews)
page on a registered device to install the `nightly` iOS preview. Tuist accepts
app bundles/IPAs/APKs independently of the project's build system. Once and
other non-Xcode/Gradle projects show Previews in the sidebar after their first
preview upload; there is no need to change the project to Xcode.

## Tuist integration and delivery

The directory was renamed from `atlas-mobile/` to `atlas-native/` to include the
CLI, but the pipeline remains `atlas-mobile.yml` and the Tuist project identity
is unchanged. Both `once.toml` and `tuist.toml` point to the existing private Once project
`tuist/atlas-mobile`. Once uses it for shared build caching and run reporting;
Tuist uses it for previews and bundle insights.

The project is connected to the `tuist/tuist` GitHub repository. GitHub jobs
use OpenID Connect for short-lived authentication, so no long-lived project
token is needed.

For local shared caching, sign in and omit `ONCE_CACHE_PROVIDER=local`:

```sh
mise exec -- once auth login --provider tuist
mise run build:android
```

`.github/workflows/atlas-mobile.yml`:

- Runs automatically only for changes under `atlas-native/`; draft pull requests
  skip all jobs. A manual dispatch remains available.
- Runs SwiftLint, Rust formatting and Clippy, and ktlint in separate lint jobs.
- Tests Rust authentication against mock discovery/registration/token responses,
  including state/PKCE validation and issuing-client preservation on refresh.
  iOS tests cover the real Rust bridge and Keychain persistence semantics with
  a process-local adapter; the simulator app includes its own Keychain entitlement.
- Builds the Rust CLI, Android, iOS and macOS in build jobs, independently of the core,
  CLI, iOS and macOS test jobs. The Swift tests exercise the adapter against the real
  Rust library.
- Retains the CLI tar archive, APK, simulator/device ZIPs and test reports as GitHub
  artifacts for 14 days. The CLI archive preserves executable permissions and
  its artifact name identifies the build host's OS and architecture.
- Uses shared caching in trusted jobs when authentication succeeds, except for
  Android, iOS device and macOS builds. These use only the local cache so distribution signing
  never consumes outputs from the shared cache used by pull requests. Forks also
  use only the local cache and have no OIDC permission.
- Publishes the APK, simulator app and signed device IPA to Tuist's `nightly`
  preview track only after all main-branch build, test and lint jobs pass.
  A manual dispatch on `main` also publishes previews. Device signing requires
  the one-time profile setup above and fails visibly if credentials are missing.
  Android distribution requires a stable signing identity; until configured,
  debug APKs remain CI artifacts rather than nightly downloads. Android and
  simulator publication precede device signing, so an iOS provisioning-profile
  update does not prevent the other previews from publishing. Credential-free
  signing guards, keychain and icon-packaging tests also gate publication. Simulator uploads use `TUIST_PREVIEW_BUILD_VERSION`
  with a fresh timestamp so cached binaries and delivery reruns do not collide
  with an existing preview. This changes only preview metadata, leaving the app's
  internal build version and signature unchanged. Device packaging already stamps
  its temporary copy before distribution signing.
- Never publishes from pull requests. Cache authentication failure can fall back
  to a local build; delivery failures remain visible.

Run language checks locally with `mise run lint:rust`,
`ONCE_CACHE_PROVIDER=local mise run lint:swift`, and `mise run lint:kotlin`.
The Rust Cargo workspace supports Clippy and editor tooling; Once excludes Cargo
manifest discovery and builds/tests the CLI, native apps and shared core directly
from its authored graph.

Delivery uses the `atlas-mobile-previews` GitHub environment. Add protection rules
there if preview publication needs approval. App Store and Google Play publishing
are intentionally not enabled; store registration and platform-specific store
credentials remain separate from internal ad-hoc distribution.
