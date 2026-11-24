---
{
  "title": "Xcode",
  "titleTemplate": ":title · Snapshots · Features · Guides · Tuist",
  "description": "Snapshot every SwiftUI preview of an Xcode project and review the changes in Tuist."
}
---
# Xcode snapshots {#xcode-snapshots}

> [!IMPORTANT]
> **Requirements**
>
> - Snapshots enabled for your account. They are currently invite-only: [reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access.
> - A project <.localized_link href="/guides/get-started/existing-xcode-project">connected to Tuist</.localized_link>.
> - iOS 17 or macOS 14 to render previews.

The [tuist/snapshots](https://github.com/tuist/snapshots) library renders every SwiftUI preview in your app to an image, so you don't write snapshot tests by hand. `tuist xcodebuild test` uploads the images after the run, and Tuist compares them with the <.localized_link href="/guides/features/snapshots#how-it-works">baseline</.localized_link>.

## Set up {#set-up}

1. In Xcode, add the `https://github.com/tuist/snapshots` package, from version `0.1.0`.
2. Create a unit test target hosted by your app, for example `AppSnapshotTests`, and link the package's `TuistSnapshotsTesting` product to it.
3. Add a test class to that target. Every preview becomes its own test:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. Add a scheme that runs the target, for example `AppSnapshots`. The scheme names the snapshot set.

## Run {#run}

Run the tests through `tuist xcodebuild test`, always on the same simulator, because a different device renders images of a different size:

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

In CI, the images the tests rendered are uploaded after the run, and the command fails when they changed and nobody approved the changes. Local runs upload nothing, because they would upload uncommitted changes.

<!-- @snippet: ./_previews-library -->
