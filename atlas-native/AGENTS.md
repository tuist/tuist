# Atlas native

This is an independent Once workspace for Atlas's native clients. The shared
Rust core owns the section catalog and destinations; the CLI is Rust, Android
uses Kotlin with platform widgets, and iOS uses SwiftUI. Native views must not duplicate catalog
strings or routes. Authentication networking and OAuth state live in the independent
Rust `auth/` crate (see `auth/AGENTS.md`); native adapters own browser presentation
and secure persistence. Automation is native (run, monitor, approve); the other
workspace sections open in the system browser and may require a separate browser
sign-in. OAuth tokens are not browser cookies. Workflow authoring remains web-first.

## Layout

- `once.toml`: typed build graph and shared cache identity (`tuist/atlas-mobile`).
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
  The signed-out screen matches Tuist's login layout with Atlas's azure palette,
  the shared Tuist mark used by Atlas's web login, and supported hosted/self-hosted actions. Keep native browser auth separate
  from presentation; restore sessions automatically rather than exposing a debug
  restore button.
- `resources/`: shared login-asset generation; see `resources/AGENTS.md`. Checked-in
  light/dark backgrounds and marks feed the iOS asset catalog and Android resources.
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

Once 0.68.2 has no Apple extension target. There is no ActivityKit/WidgetKit extension,
APNs/FCM registration, background push or real-device activity validation in this slice.
Do not keep sockets alive in suspended apps or claim background delivery. Adding those
surfaces requires build-system support, actual device signing and notification services.

## Boundaries

- Navigation C strings are immutable, process-lifetime pointers. Never free them
  in Swift. Authentication responses are separately owned allocations: release each
  exactly once with `atlas_auth_free` and never log requests/results.
- Navigation JNI exports accept only integer values and opaque pointers; they never
  dereference JNI pointers. Authentication uses the `jni` crate for VM string ownership.
  Keep UTF-8 decoding and boundary checks covered by tests.
- Rust auth calls are synchronous and bounded; invoke them from a background executor,
  never the UI thread. Serialize session changes/refresh rotation in native coordinators,
  not through an app-wide lock that would block unrelated future API requests.
- iOS uses ThisDeviceOnly Keychain entries and a simulator-specific Keychain entitlement;
  device builds must derive their entitlement from the actual signing team/profile.
  Once's iOS XCTest agent is unhosted and cannot access app Keychain; test
  storage request/failure semantics with a per-test adapter, not mutable global stubs.
  Android uses AES-GCM with Android Keystore
  keys and backup-disabled encrypted preferences. Native code must successfully persist
  credentials before publishing signed-in state. Retain credentials on transient refresh
  failures, and discard rejected registrations so the next login can register again.
- `mise run prepare:rust` materializes locked third-party sources in ignored `.once/vendor`.
  Build/test tasks depend on it; run it before invoking Once directly on a clean checkout.
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
- Mobile builds are arm64 Android debug APKs and arm64 iOS simulator apps. Store
  delivery requires separate device targets, signing, app icons and store setup.
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
- Main-branch delivery uses the `nightly` Tuist preview track, gated by all build,
  test and lint jobs. Forks use local caching and no OIDC; no PR publishes previews.
