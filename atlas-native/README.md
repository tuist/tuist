# Atlas native

Native clients for Atlas, with a shared Rust core and builds powered by
[Once](https://github.com/tuist/once).

| Layer | Technology |
| --- | --- |
| Shared core | Rust, exposed through a C ABI and JNI |
| Command line | Rust, using the shared core directly |
| Android | Kotlin and native Android widgets |
| iOS | Swift and SwiftUI |
| Build, test and cache | Once |
| Internal distribution | [tuist/atlas-mobile](https://tuist.dev/tuist/atlas-mobile) |

The initial app presents Accounts, Tasks and Notes using the shared Rust catalog.
Selecting a section opens its authenticated Atlas page in the system browser.
Authentication remains in the browser; the app does not yet fetch Atlas data,
store tokens, or provide offline editing. This is a starting point for native
features, not a WebView wrapper or a completed native Atlas client.

## Develop

Run all commands from `atlas-native/`. It is a separate Once workspace, so the
Atlas server's graph and cache remain unchanged.

```sh
cd atlas-native
mise install rust github:tuist/once
ONCE_CACHE_PROVIDER=local mise run check
```

The toolchain pins Once 0.67.1, Rust 1.96.0, Kotlin 2.4.10 and ktlint 1.7.1.
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
Use an arm64 emulator or device. Once signs previews with a debug key; these are
not Play Store release bundles.

### iOS

On Apple Silicon macOS with Xcode and an iOS simulator runtime installed:

```sh
mise exec -- rustup target add aarch64-apple-ios-sim
ONCE_CACHE_PROVIDER=local mise run build:ios
ONCE_CACHE_PROVIDER=local mise run test:ios
xcrun simctl install booted .once/out/AtlasIOS/Atlas.app
xcrun simctl launch booted dev.tuist.atlas
```

The app supports iOS 17+ and links the Rust core statically. The current target
builds for arm64 simulators, not physical devices or TestFlight.

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
- Builds the Rust CLI, Android and iOS in build jobs, independently of the core,
  CLI and iOS test jobs. The Swift tests exercise the adapter against the real
  Rust library.
- Retains the CLI tar archive, APK, simulator ZIP and test reports as GitHub
  artifacts for 14 days. The CLI archive preserves executable permissions and
  its artifact name identifies the build host's OS and architecture.
- Uses shared caching in trusted jobs when authentication succeeds. Forks build
  with only the local cache and have no OIDC permission.
- Publishes the built artifacts to Tuist's `nightly` preview track only after all
  main-branch build, test and lint jobs pass. A manual dispatch on `main` also
  publishes previews.
- Never publishes from pull requests. Cache authentication failure can fall back
  to a local build; delivery failures remain visible.

Run language checks locally with `mise run lint:rust`,
`ONCE_CACHE_PROVIDER=local mise run lint:swift`, and `mise run lint:kotlin`.
The Rust Cargo workspace supports Clippy and editor tooling; Once excludes Cargo
manifest discovery and builds/tests the CLI, native apps and shared core directly
from its authored graph.

Delivery uses the `atlas-mobile-previews` GitHub environment. Add protection rules
there if preview publication needs approval. App Store and Google Play publishing
are intentionally not enabled: they require device/release targets, signing
identities, store registrations and platform-specific distribution credentials.
