---
{
  "title": "Gradle previews",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Build and share Android apps and native command-line tools from Gradle projects with Tuist Previews."
}
---
# Gradle previews

Build and share Android apps and native command-line tools directly from Gradle. Start with the <.localized_link href="/guides/get-started/gradle-project">Gradle project guide</.localized_link> to connect the project and authenticate.

## Android apps

```bash
./gradlew :app:tuistShareDebug
```

The `dev.tuist` settings plugin registers a `tuistShare<Variant>` task for each application variant from the Android Gradle Plugin (8.8.2 or later). Replace `app` and `Debug` with your application module and variant, for example `:app:tuistShareDemoDebug` for a product flavor. The task builds the APK through Gradle's declared artifact dependencies before publishing it. It also works when build outputs are up to date or restored from the build cache.

Only a single, signed, universal application APK is supported. Android's debug variant normally uses a debug signing key; release variants need your own signing configuration. The task verifies the APK signature before authentication or upload. Unsigned, invalid, instrumentation, and split APKs are rejected. Library modules, test APKs, and Android App Bundles (`.aab`) are not publication targets.

## Native command-line tools

Projects using Gradle's `cpp-application` or `swift-application` plugin get a share task for each native binary:

```bash
./gradlew :app:tuistShareMainDebug
```

The task builds and packages the installed distribution, including its launcher and runtime libraries. Use `tuistShareMainRelease` for the release binary. Projects targeting multiple machines have a task for each binary; run `./gradlew :app:tasks --all` to find their names.

Native macOS and Linux executables for arm64 or x86_64 are supported. Build on the target platform with the toolchain required by your Gradle plugin. JVM applications and their generated launcher scripts are not supported by this integration.

## Publication behavior

Share tasks publish using the plugin's existing Tuist credentials, without invoking the Tuist CLI. Ordinary `assemble`, `build`, and test tasks never publish previews.

After sharing, open **Previews** in your project to copy the link. Repeating a share of the same build and track reuses its publication, including after a build-cache hit. Failed or unconfirmed uploads fail the share task; they are not reported as successful previews.

## CI and tracks

Configure <.localized_link href="/guides/integrations/continuous-integration">CI authentication</.localized_link> with the same credentials you use for the plugin's other authenticated features, then request publication explicitly:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Add `--track nightly` to a native share task in the same way. Tasks use the configured Tuist project, server URL, and proxy settings. Preview publication always requires authentication. Git revision metadata, release notes, and automatic pull-request comments are not attached by these tasks.

Artifact publications expire after 30 days on hosted Tuist. Self-hosted instances use `TUIST_APP_PREVIEW_RETENTION_DAYS`; leaving it unset disables expiry for this family. Expired publications cannot be revived by repeating the same intent.

## Share an existing APK

For an APK built outside this workflow, or to include release notes with the legacy upload flow, the CLI remains available:

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

See <.localized_link href="/guides/features/previews#run-a-preview">Run a preview</.localized_link> for running published builds, access, tracks, and README badges.

<!-- @snippet: ./_tuist-share -->
