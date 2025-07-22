---
title: "Tuist is now available on the App Store"
category: "product"
tags: ["product"] 
excerpt: "Download the new Tuist iOS app to access your Tuist Previews on the go"
author: fortmarek
og_image_path: /marketing/images/blog/2025/07/22/tuist-ios-app/og.jpg
highlighted: true
---

We are strong believers in leveraging the platforms we build for as much as we can and dogfooding our work to have strong empathy for anyone using our platform. While in some cases, it means we need to juggle multiple pieces (be it our CLI, server or the macOS app), we strongly believe this is the best way to build software for developers.

But while the majority of teams using Tuist are building an iOS app, we haven't had an opportunity to build and integrate with this platform, until now.

We're really excited to announce that Tuist is now available on the App Store. We're starting with streamlining accessing and running Tuist Previews, but we have more in store for the future.

[![Download on the App Store](/marketing/images/blog/2025/07/22/tuist-ios-app/download-app-store.png)](https://apps.apple.com/us/app/tuist/id6748460335)

<img alt="Download on the App Store" src="/marketing/images/blog/2025/07/22/tuist-ios-app/tuist-app.png" width="300">

Delivering a high-quality iOS app is not easy. To ensure the best experience for your users, you need to test apps often, otherwise, bugs will inevitably creep in. And the best time to test a new feature is still in the PR stage. Instead of checking out a branch and compiling the changes, a time-consuming process, teams often fully re-test the new changes from a nightly build. But at that point, it's really difficult to pinpoint when a regression was introduced. 

[Tuist Previews](https://docs.tuist.dev/en/guides/features/previews) aim to solve this problem by providing an extremely easy way to test your app. What started as a CLI command to share apps via links has evolved into a comprehensive ecosystem of tools that bring testing closer to where development and QA teams actually work. We've already made installing previews on macOS as easy as clicking a button with our [menu bar app](/blog/2024/08/28/tuist-macos-app). Now, we're taking the same step on iOS with our Tuist app, creating a unified experience across Apple's platforms.

## Tuist app features

In the Tuist app, you can see the latest previews for your projects – and you can tap on any preview to see it in detail, such as to see who created the preview or which commit it's related to. In both the list of previews and the detail view, there's a "Run" button that allows you to run the preview directly on your device.

Additionally, clicking on any preview link – or scanning a QR code – will open the preview in the Tuist app:

<img alt="Download on the App Store" src="/marketing/images/blog/2025/07/22/tuist-ios-app/tuist-ios-app.gif" width="300">

To see the app in action, you can also watch the following video:
<iframe title="Tuist iOS app" width="560" height="315" src="https://videos.tuist.dev/videos/embed/dYZAKZqx75PGWetFjZj2QA" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>

## Native developer experiences for native engineers

While the app is currently laser-focused on previews, the app is also a foundation block for us to build more native features for Tuist. Imagine triggering a release build or running a QA agent directly from your phone – and having a live activity that tracks the progress. These kinds of native developer experiences have been missing from the iOS ecosystem and we hope to fill in the gap.

Let us know your feedback over at our [community forum](https://community.tuist.dev/) or [Slack](https://tuist.dev/slack). And since the [app](https://github.com/tuist/tuist/tree/main/app) is fully open-source and written in SwiftUI, this might be the perfect opportunity for you to get involved with open source if you'd like to improve the app yourself.
