---
title: "Evolving Previews With the Tuist SDK and Tracks"
category: "product"
tags: ["product"]
excerpt: "Keep everyone on the latest version with the new Tuist SDK and Tracks."
author: fortmarek
og_image_path: /marketing/images/blog/2026/01/02/previews-sdk-and-tracks/og.jpg
highlighted: true
---

Over a year ago, we [introduced Tuist Previews](/blog/2024/08/06/url-centric-collaboration) with a simple premise: sharing an app should be as easy as sending a link. The traditional flow of building, signing, and pushing to TestFlight was too cumbersome for quick feedback loops.

Initially, we focused on minimizing friction for developers, introducing features like [posting comments directly in your pull requests](https://docs.tuist.dev/en/guides/features/previews#pullmerge-request-comments), allowing anyone to click a link and start testing without checking out a branch or waiting for a local build.

But as teams adopted previews, it became clear we needed to expand our primary audience beyond engineers. Product managers wanted to see features before they shipped. QA teams needed consistent access to the latest builds. Leadership wanted to stay informed about what's coming.

Today, we're taking the first steps in that direction with the new **Tuist SDK** and **tracks**.

## The Tuist SDK: In-app update notifications

Here's a common problem: you share a preview with a tester, they find an issue, you fix it and share a new preview. But the tester is still using the old build. They don't know a new version is available.

The [Tuist SDK](https://github.com/tuist/sdk) solves this by enabling your app to detect when a newer preview is available and notify users. Add the SDK to your project:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

Then start monitoring for updates:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

When a newer preview is available, the SDK will present an alert prompting the user to update:

<img alt="Preview update alert" src="/marketing/images/blog/2026/01/02/previews-sdk-and-tracks/preview-update-alert.png" style="max-width: 300px;">

> Update checking is automatically disabled on simulators and App Store builds, so you don't need to worry about conditional compilation.

For more control, you can perform a single update check instead of continuous monitoring:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

## Tracks: Control which updates to notify about

By default, the SDK checks for updates within the same git branch. A preview built from `main` will only notify about newer previews also built from `main`. This works well for PR-based workflows, but what about nightly builds, beta releases, or internal testing that aren't tied to a specific branch?

Tracks let you organize previews into named groups and control which updates the SDK notifies about:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Tracks are lazily created – specify a track name and it will be created automatically if it doesn't exist. When you share a preview with `--track beta`, the SDK will only notify users about newer previews on the `beta` track.

This is useful for several scenarios:
- **Beta testing**: Share stable builds with external testers on a `beta` track, keeping them on vetted releases rather than every commit
- **Nightly builds**: Automate nightly builds to a `nightly` track for internal QA
- **Feature demos**: Create a `demo` track for product reviews and stakeholder presentations

## What's next

We're excited to take previews even further. We will soon start working on [distribution groups](https://github.com/tuist/tuist/issues/8940) – the ability to define groups of users who should receive specific previews. You will be able to add your QA team to a `qa` group and having them automatically notified whenever a new preview is shared to the `nightly` track.

We're also exploring Android support. As previews expand beyond engineering, teams expect a single way to share their apps – regardless of platform. A product manager shouldn't need different tools to test iOS and Android builds. QA teams shouldn't have to learn separate workflows. With Android support, you'd share previews the same way across both platforms, and testers would receive updates through the same SDK. If your team builds for both platforms and you're interested in bringing previews to Android, [reach out to us](mailto:contact@tuist.dev) – we'd love to hear about your use case.
