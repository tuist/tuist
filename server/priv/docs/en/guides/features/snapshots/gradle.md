---
{
  "title": "Gradle",
  "titleTemplate": ":title · Snapshots · Features · Guides · Tuist",
  "description": "Snapshot every Compose preview, or upload what Paparazzi and Roborazzi record, with the Tuist Gradle plugin."
}
---
# Gradle snapshots {#gradle-snapshots}

> [!IMPORTANT]
> **Requirements**
>
> - Snapshots enabled for your account. They are currently invite-only: [reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access.
> - The <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</.localized_link>.
> - [Paparazzi](https://github.com/cashapp/paparazzi) or [Roborazzi](https://github.com/takahirom/roborazzi) in the modules you snapshot.

The Tuist Gradle plugin uploads the images Paparazzi and Roborazzi record, and Tuist compares them with the <.localized_link href="/guides/features/snapshots#how-it-works">baseline</.localized_link>. In modules that apply Paparazzi, the plugin also generates a test that renders every Compose `@Preview`, so you don't write snapshot tests by hand.

## Set up {#set-up}

Enable snapshots in your `settings.gradle.kts`:

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## Run {#run}

In CI, `./gradlew test` renders the previews and uploads them, and the build fails when they changed and nobody approved the changes. Local runs upload nothing, because they would upload uncommitted changes. Pass `-Ptuist.snapshots=false` to turn uploads off in CI.

The Paparazzi and Roborazzi record tasks, such as `recordPaparazziDebug`, always upload when snapshots are enabled.

## Options {#options}

The `snapshots` block takes these options:

- `enabled`: whether snapshots are uploaded. Defaults to `false`.
- `set`: the set builds are compared within. Defaults to the Gradle project's path.
- `directory`: the directory with the images to upload, relative to the Gradle project. Defaults to where the generated preview test or the snapshot library writes.
- `failOnChanges`: whether the build fails on changes nobody approved. Defaults to `true`.
- `diffThreshold`: the share of pixels, from 0 to 1, that may differ before an image counts as changed. Defaults to `0`.
- `previews { generateTests }`: whether the Compose preview test is generated. Defaults to `true`.
- `previews { packageTrees }`: the packages scanned for previews. Defaults to the Android namespace.
- `previews { includePrivatePreviews }`: whether private `@Preview` functions are rendered too. Defaults to `false`.
- `previews { theme }`: the Android theme previews are rendered in. Defaults to Paparazzi's.
