# Tuist App (Android)

This node covers the Tuist Android companion app under `android/`. The app provides OAuth authentication and project management, mirroring the iOS app's functionality.

## Project Structure
- `app/src/main/java/dev/tuist/app/` - Main app source
  - `MainActivity.kt` - Entry point, deep link handling, environment switching
  - `TuistApplication.kt` - Hilt application class
  - `data/` - Data layer (auth, network, models, environment config)
  - `navigation/` - Navigation graph and routes
  - `ui/` - Compose UI (theme, login screen, projects screen)
- `app/src/main/res/` - Resources (icons, drawables, strings, themes)

## Technology Stack
- **Language**: Kotlin
- **UI**: Jetpack Compose + Material 3
- **DI**: Hilt
- **Networking**: Retrofit + OkHttp + Moshi. Both API clients use `CertificateTrust.clientBuilder`; the singleton Coil factory explicitly installs a separate unauthenticated policy client and disables service-loader network fallbacks.
- **TLS policy**: Embed all twelve SPKI keys, synchronized by `infra/certificate-trust` Go tests. Preserve the original socket/engine validator, then inspect the complete hostname-aware native constructed path via `X509TrustManagerExtensions`. Never inspect only the peer-supplied chain or mutate global defaults/stores. Keep `PolicyTrustManager` and its hostname/configuration methods under R8: Android discovers them reflectively. API 26/27 must not invoke API-28-only `isSameTrustConfiguration`.
- **CT gate**: The app targets API 35 without Network Security Config CT opt-in. Before enabling CT or raising that target, preserve TLS-extension/OCSP SCT data in the second validation (newer five-argument API where supported) and qualify CT-enforcing devices; hostname-only revalidation can otherwise reject valid SCT-only servers.
- **Generated API enums**: Use `UPPERCASE` identifiers while preserving generated `@Json` wire values. `original` naming generates invalid Kotlin for an empty-string enum. `GeneratedEnumTest` pins the empty-string round trip; never hand-edit generated models or the server specification.
- **Token Storage**: EncryptedSharedPreferences
- **OAuth**: Chrome Custom Tabs with PKCE flow
- **Token refresh**: `TokenRefreshAuthenticator` exchanges the OAuth refresh token at `POST /oauth2/token` (`grant_type=refresh_token` + the app's client id). `/api/auth/refresh_token` only accepts CLI (Guardian) refresh tokens. Only `400 invalid_grant`/`401`, or a 200 without a token pair (the server can no longer mint tokens, e.g. deleted user), sign the user out; other failures surface as `TokenRefreshException` (an `IOException`) and keep the tokens.
- **Navigation**: Navigation Compose

## Building
- Build debug APK: `cd android && ./gradlew assembleDebug`
- Build release bundle: `cd android && ./gradlew bundleRelease` (requires signing config)
- Publish to Google Play: `cd android && ./gradlew publishReleaseBundle` (requires service account)

## Certificate Trust Qualification

- `./gradlew testDebugUnitTest assembleDebug`: unit tests include generated-key differential TLS tests on Robolectric API 26/28/35. The JVM validator adapter is not real Conscrypt qualification.
- `./gradlew assembleDebugAndroidTest minifyReleaseWithR8`: compile the native tests and verify shrinker retention. R8 compilation is not a signed/released APK runtime check.
- Run `CertificateTrustDeviceTest` only on an explicitly selected owned device/emulator. Public controls are opt-in through runner argument `tuistTrustLive=true`; no credentials are sent. Keep native reference controls separate from production retry behavior. Require certificate causes, not arbitrary network/TLS failures. Generated root/leaf denies prove the application hook even when the OS already rejects public controls.
- Native API 35 arm64 emulator tests passed: real `TrustManagerImpl` private-root differential and default NSC `RootTrustManager` root/leaf differentials, normal-verification failures and public controls. Device API 26/28, custom per-domain NSC/private anchors, CT, physical devices, release artifacts and installed-client upgrades remain separate gates. Browser OAuth stays with the external browser/OS owner.

## Running on Emulator

The debug build defaults to production (`https://tuist.dev`). In debug builds you can override the environment at launch time via an intent extra:

```bash
# Force-stop and launch with a specific environment
adb shell am force-stop dev.tuist.app && adb shell am start -n dev.tuist.app/.MainActivity --es environment staging
```

Valid environments:
| Name | Server URL | OAuth Client ID |
|------|-----------|----------------|
| `development` | `http://localhost:8080` | `5339abf2-467c-4690-b816-17246ed149d2` |
| `staging` | `https://staging.tuist.dev` | `bcb85209-0cef-4acd-8dd4-e0d1c5e5e09a` |
| `canary` | `https://canary.tuist.dev` | `ca49d1d6-acaf-4eaa-b866-774b799044db` |
| `production` | `https://tuist.dev` | (from BuildConfig) |

The selected environment persists in SharedPreferences across launches until explicitly changed. Switching environments signs out the current user and restarts the app process so Hilt singletons are recreated.

For release builds, the environment is always `production`.

## Icons

Adaptive icon with three layers:
- **Background**: Gradient shape (`drawable/ic_launcher_background.xml`) — `#7135FF` to `#3D00A5`
- **Foreground**: Tuist shell logo with gradient fill and white stroke — PNG in `mipmap-*/ic_launcher_foreground.png`
- **Monochrome**: Solid black silhouette for Material You themed icons — PNG in `mipmap-*/ic_launcher_monochrome.png`

Source SVGs are generated from the Figma design and rendered to PNGs at 5 densities (mdpi=108, hdpi=162, xhdpi=216, xxhdpi=324, xxxhdpi=432) using `rsvg-convert`.

## Publishing

The `release-android` job in `.github/workflows/release.yml` handles publishing to Google Play's internal track. Secrets are read from 1Password:
- Keystore binary: `op document get "Google Play release.keystore binary" --vault tuist`
- Keystore/key password: `op://tuist/Google Play release.keystore/password`
- Service account JSON: `op://tuist/Google Play release.keystore/sirudpicoo6z2b3rmdtfhcj3aa`

## Code Style
- Follow idiomatic Kotlin and Jetpack Compose conventions.
- Do not add one-line comments unless truly useful.
