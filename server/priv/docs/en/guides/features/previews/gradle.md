---
{
  "title": "Gradle previews",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Build and share signed Android APKs from Gradle projects with Tuist Previews."
}
---
# Gradle previews

Build your Android application with Gradle, then share the APK with the Tuist CLI. Start with the <.localized_link href="/guides/get-started/gradle-project">Gradle project guide</.localized_link> to connect the project and authenticate.

## Build and share

```bash
./gradlew :app:assembleDebug
tuist share app/build/outputs/apk/debug/app-debug.apk
```

Replace `app` and the APK path with your module and variant. Android's debug variant normally uses a debug signing key. Release APKs must be signed with your own signing configuration before sharing. Share an installable APK, not an Android App Bundle (`.aab`).

The command returns a preview link. Recipients with an Android device or emulator connected through ADB can run:

```bash
tuist run {url}
tuist run --device "Pixel_6" {url}
```

You can also download the APK from the preview page and install it on an Android device that permits installation from that source.

## CI and tracks

Configure <.localized_link href="/guides/integrations/continuous-integration">CI authentication</.localized_link>, then share only after the application build succeeds:

```bash
./gradlew :app:assembleDebug
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

The Gradle plugin's caching and build/test reporting do not implicitly publish previews. Keep the `tuist share` step explicit in the workflows where you want distribution.

See the <.localized_link href="/guides/features/previews">Previews overview</.localized_link> for project visibility, tracks, release notes, and sharing links.
