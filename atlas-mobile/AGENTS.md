# Atlas mobile

This is an independent Once workspace for Atlas's mobile clients. The shared
Rust core owns the section catalog and destinations; Android uses Kotlin with
platform widgets, and iOS uses SwiftUI. Native views must not duplicate catalog
strings or routes. The initial app opens authenticated Atlas pages in the system
browser. It does not implement a native API client or store Atlas credentials.

## Layout

- `once.toml`: typed build graph and shared cache identity (`tuist/atlas-mobile`).
- `core/src/`: shared navigation, C ABI, and primitive-only JNI bridge.
- `core/Cargo.toml`: editor and Clippy support, not the native build graph.
- `core/include/`: authored C header and Clang module map imported by Swift.
- `android/`: Kotlin UI, JNI adapter, Android manifest and resources.
- `ios/`: SwiftUI app, Swift adapter, Info.plist and Swift Testing bridge tests.
- `mise.toml` / `mise.lock`: pinned Once, Rust, Kotlin and ktlint toolchains.
  The local postinstall hook prevents unrelated monorepo CLI bootstrapping.
- `tuist.toml`: Tuist preview and bundle-inspection project configuration.

## Validation

Run commands from this directory, not the monorepo root:

```sh
ONCE_CACHE_PROVIDER=local mise run check
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
`ANDROID_NDK_HOME` (CI pins 27.3.13750724). iOS needs Apple Silicon macOS, Xcode,
and an installed iOS simulator runtime. Do not switch this workspace to Gradle,
SwiftPM, or generated Xcode projects to work around Once build failures.

## Boundaries

- C strings are immutable, process-lifetime pointers. Never free them in Swift.
- JNI exports accept only integer values and opaque environment/object pointers;
  they never dereference JNI pointers. Invalid indices return a sentinel, not a
  panic. Keep UTF-8 decoding and boundary checks covered by tests.
- The Android package, Kotlin class/method names and JNI exported symbols must
  agree. Renaming any of these requires rebuilding and launching the Android app.
- `Info.plist` is a complete template, not a merge into Once's default plist.
  Keep its identifier, executable, families and supported platform consistent
  with the manifest, and smoke-test simulator installation after changes.
- These builds are arm64 Android debug APKs and arm64 iOS simulator apps. Store
  delivery requires separate device targets, signing, app icons and store setup.
- GitHub CI uses the existing private Once project. Its repository connection to
  `tuist/tuist` is required for OIDC authorization. Do not put project tokens,
  signing passwords, or service account credentials in source or cached actions.
- The single `.github/workflows/atlas-mobile.yml` pipeline triggers automatically
  only for `atlas-mobile/**` changes and skips draft PRs. Keep building, testing
  and each language's linting in distinct jobs. There is no unconditional merge
  queue trigger because it cannot apply GitHub path filters.
- Main-branch delivery uses the `nightly` Tuist preview track, gated by all build,
  test and lint jobs. Forks use local caching and no OIDC; no PR publishes previews.
