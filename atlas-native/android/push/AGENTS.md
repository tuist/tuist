# Android push packaging

Atlas uses the official Firebase Messaging Android SDK, not a homemade FCM client.
Once 0.68.2 has no Maven/AAR importer, so `modules/firebase.star` supplies its existing
`android_library` provider with verified jars, compiled AAR resource zips, and a jar
of library-package R classes. Keep this boundary separate from application state.

## Reproducibility and upgrades

- `dependencies.lock.json` pins the full artifact closure, URLs, SHA-256 digests,
  packaging and dependency edges. `mise run lock:android` is the explicit online
  upgrade path. The bounded POM resolver fails on unsupported dynamic versions,
  rather than pretending to implement all of Maven. Review the resulting closure.
- `mise run prepare:android` verifies downloads and materializes only generated
  files under `.once/vendor-maven`. Keep this separate from Cargo's `.once/vendor`:
  Cargo can remove directories that are not Rust dependencies. No binary SDKs are
  committed. Kotlin stdlib is supplied by the pinned Kotlin toolchain; importing a
  second copy makes d8 fail on duplicate classes. Native-library/assets-bearing
  AAR upgrades fail until their packaging is explicitly supported.
- `manifest.py` checks every locked AAR manifest against the authored application
  manifest. The only omitted components are FirebaseInitProvider (explicit
  FirebaseOptions initialization in AtlasApplication) and FirebaseMessagingService
  (replaced by the app's subclass). Never silently ignore a new registrar,
  permission, exported flag or SDK minimum.
- `resources.py build` links the exact application and library resource set,
  including the same overlay order as Once, with `--extra-packages` for AAR R
  namespaces. `resources.py verify` compares every generated app resource ID with
  `aapt2 dump resources` of the final APK. This gate is part of `build:android`,
  including credential-free PR builds. Change it together with app versions,
  resource ordering, SDK settings or Once's linker behavior. Do not ship on a
  successful compilation without this check.
- The importer includes the complete transitive runtime closure and lets Once's
  normal d8/multidex/signing pipeline package it. Do not introduce Gradle just for
  Firebase or put provider credentials into cached build actions.

## Project configuration

`android/res/values/push.xml` contains public Firebase Android app identifiers.
Empty values disable Firebase initialization. To configure a real project, download
its **Android** `google-services.json` for `dev.tuist.atlas` and run:

```sh
python3 android/push/configure.py /path/to/google-services.json
```

Review/commit the four public identifiers and rebuild. Restrict the public API key
appropriately and use the stable Android signing certificate, not an ephemeral CI
debug certificate. The server's service-account JSON belongs only in server runtime
secrets and must be authorized for the same Firebase project. The configuration
importer rejects service-account JSON. Analytics and FCM auto-init are disabled;
only explicit foreground opt-in requests a token.

## Validation

```sh
python3 android/push/push_test.py
mise run prepare:android
ANDROID_HOME=... ANDROID_NDK_HOME=... ONCE_CACHE_PROVIDER=local mise run build:android
mise run lint:kotlin
```

The portable tests cover digest tampering, stale extraction, configuration isolation,
manifest drift and final-APK resource mismatch. On a Play-enabled physical device,
also test permission allowed/denied, token refresh, foreground/background/process-dead
alerts, wrong-origin/old-registration rejection and sign-out/account replacement.
A debug APK with empty identifiers proves packaging, not live push delivery.
