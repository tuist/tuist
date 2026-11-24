---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Snapshots · Features · Guides · Tuist",
  "description": "Snapshot every SwiftUI preview of a Tuist generated project and review the changes in Tuist."
}
---
# Generated Xcode project snapshots {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **Requirements**
>
> - Snapshots enabled for your account. They are currently invite-only: [reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access.
> - A project <.localized_link href="/guides/get-started/generated-xcode-project">connected to Tuist</.localized_link>.
> - iOS 17 or macOS 14 to render previews.

The [tuist/snapshots](https://github.com/tuist/snapshots) library renders every SwiftUI preview in your app to an image, so you don't write snapshot tests by hand. `tuist test` uploads the images after the run, and Tuist compares them with the <.localized_link href="/guides/features/snapshots#how-it-works">baseline</.localized_link>.

## Set up {#set-up}

Add the package to `Tuist/Package.swift`:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

Then add a unit test target that depends on your app and on `TuistSnapshotsTesting`, and a scheme that runs it. The scheme names the snapshot set:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

Add a test class to the target. Every preview becomes its own test:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

Run `tuist install` to fetch the package.

## Run {#run}

Run the scheme with `tuist test`, always on the same simulator, because a different device renders images of a different size:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

In CI, the images the tests rendered are uploaded after the run, and the command fails when they changed and nobody approved the changes. Local runs upload nothing, because they would upload uncommitted changes.

> [!TIP]
> With <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>, a snapshot test target is only skipped once its images passed or were approved, so a rerun can't skip a target whose changes nobody reviewed. When a run skips targets, the images it didn't render count as skipped, not removed.

<!-- @snippet: ./_previews-library -->
