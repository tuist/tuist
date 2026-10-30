# Android companion app

Kotlin/Compose app with Hilt, Retrofit, and OAuth PKCE through Chrome Custom Tabs.

## Development

Run from `android/`: `./gradlew assembleDebug`. Release builds use
`./gradlew bundleRelease` and require signing configuration; publishing is handled
by the `release-android` job in `.github/workflows/app-release.yml`.

Debug builds default to production. Select an environment with:

```bash
adb shell am force-stop dev.tuist.app
adb shell am start -n dev.tuist.app/.MainActivity --es environment staging
```

Valid environments are `development`, `staging`, `canary`, and `production`;
their URLs and OAuth client IDs belong in the environment configuration, not here.
The selection persists across launches. Switching environments signs out the user
and restarts the process to recreate Hilt singletons. Release builds always use
production.

## Authentication and build isolation

- Refresh OAuth tokens at `POST /oauth2/token` with `grant_type=refresh_token`
  and the issuing app client ID, not the CLI-only `/api/auth/refresh_token`.
  Sign out only for `400 invalid_grant`, `401`, or a token-less 200; other failures
  throw `TokenRefreshException` (`IOException`) while retaining credentials.
- Keep build configuration project-local. KSP's `ksp.project.isolation.enabled`
  and Play Publisher's `isolatedSingleProject` are required for Isolated Projects
  (only `:app` publishes). On plugin upgrades, verify assembly, JVM tests,
  configuration-cache reuse, and publishing task graphs with
  `-Dorg.gradle.unsafe.isolated-projects=true`.

## Certificate trust

- API, token-refresh, and Coil clients use `CertificateTrust.clientBuilder`.
  Keep native platform/enterprise trust and hostname checks authoritative, then
  reject denied keys in the complete `X509TrustManagerExtensions` evaluated path,
  including anchors not served by the peer. Do not replace roots or global defaults.
- Keep `PolicyTrustManager`'s reflective hostname/configuration methods under R8.
  API 26/27 must not invoke API-28-only `isSameTrustConfiguration`.
- The app targets API 35 without CT opt-in. Before enabling CT or raising that
  target, preserve TLS-extension/OCSP SCT inputs during revalidation and qualify
  CT-enforcing devices; the hostname-only API cannot carry those inputs.
- Run `./gradlew testDebugUnitTest assembleDebug assembleDebugAndroidTest`.
  Robolectric's JVM path adapter is not native Conscrypt qualification. Run
  `CertificateTrustDeviceTest` on a selected connected device; public controls
  require `-Pandroid.testInstrumentationRunnerArguments.tuistTrustLive=true`.
  Browser OAuth remains governed by the external browser/OS.

## Icons

Keep adaptive background, foreground, and monochrome layers aligned. Render source
SVGs with `rsvg-convert` at mdpi=108, hdpi=162, xhdpi=216, xxhdpi=324, xxxhdpi=432.
Only add one-line comments when they explain something non-obvious.
