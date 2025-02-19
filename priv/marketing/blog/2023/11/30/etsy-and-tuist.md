---
title: "Etsy's Journey with Tuist: A Deep Dive into Modularity and Rapid Iteration"
category: "community"
tags: ["Etsy", "SwiftUI", "UIKit", "Modularity", "VIPER"]
type: interview
excerpt: "Etsy evolves its decade-long monolithic iOS app with Tuist, paving the way for modular development. With nearly 50 iOS engineers, they leverage Tuist for streamlined module creation and emphasize a unified approach to architecture. Transitioning to SwiftUI and adopting Preview Driven Development, Etsy champions rapid iteration, testability, and consistent quality. Their tech journey reflects innovation at its best. "
interviewee_name: Mike Simons
interviewee_role: Staff iOS engineer at Etsy
interviewee_url: https://hachyderm.io/@Waltflanagan
interviewee_x_handle: waltflanagan
interviewee_avatar: /images/interviewees/mike-simons.jpg
---

[Etsy](https://www.etsy.com/), a global marketplace for handmade, vintage, and creative goods has consistently been exploring innovative ways to refine our craft. Historically, this commitment has translated into practices like seamless continuous deployment for both web and mobile applications, along with the implementation of blameless post-mortems. Today, they embody this commitment by embracing Tuist and the principles of modularity, driving them forward in their pursuit of engineering excellence.
With a substantial iOS engineering team and a history spanning a decade with a monolithic app, Etsy’s recent shift towards modularity presents an intriguing case study. It demonstrates how Tuist plays a pivotal role in facilitating this transformation and expanding their iOS project.

## Organization and Team Structure

**Could you shed light on the current composition and structure of Etsy’s iOS team, particularly focusing on its size and functionality?**

Our iOS team at Etsy is growing towards 50 engineers, where ~25% are primarily focused on platform support for the remaining 75%, who are distributed across various product teams. These product teams are quite dynamic, blending the expertise of product managers, designers, and engineers from other platforms to function seamlessly.

## Development Environment

**How does Etsy’s iOS team manage the development environment and reduce barriers to code commits?**

We are deeply invested in making the development environment as friendly and barrier-free as possible. We place a huge emphasis on automating most of the machine setup so that developers can start building and running projects almost instantly. Although Xcode is fundamental, other tools like [Fastlane](https://fastlane.tools/) significantly aid in CI orchestration and certificate management. Additionally, we maintain an in-house Swift CLI package to build custom CI functionalities, manage build logs, and interact with [Google Cloud](https://cloud.google.com/) for screenshot testing, among other tasks.
After a basic installation, scripts automate the rest, ensuring that tools like Tuist and Ruby, specified in their `.ruby_version` file, are properly set up.

## Project Architecture: From Monolith to Modules

### Tuist’s Role in Modularity

**Could you elaborate on how Tuist has influenced Etsy’s modular development and its impact on engineer contribution to architecture?**

Our iOS app was a monolith for nearly a decade. As we scaled, modularity became essential. Today, our transition is well underway, moving from a single block to a component-based architecture. The journey began with just five modules, but today we boast 35 modules, with more in the pipeline.

We promote a democratic approach where any engineer can contribute to the architecture or introduce new modules. Through what we describe as a [“conversational approach to architecture,”](https://martinfowler.com/articles/scaling-architecture-conversationally.html) we aim to align individual decisions with larger architectural goals.

Tuist became an integral part of our modularity journey. It empowered any engineer, irrespective of their experience with Apple frameworks or dependency management, to create a module. With Tuist’s swift interface, the complexity of framework creation and dependency management became a thing of the past, allowing engineers to center their attention on the business domain problems.

One thing we hope for is more customizability from Tuist, like defining custom focus modes. This would simplify tasks for engineers and abstract away unnecessary implementation details.

> Tuist empowered any engineer, irrespective of their experience with Apple frameworks or dependency management, to create a module.

### Leveraging Tuist’s Project Description Helpers

**How does Etsy ensure consistent and streamlined module creation?**

To streamline the creation of modules, we devised a `Module` protocol. It provides a blueprint for engineers to follow, and it also offers default functionalities for things like test targets and demo apps. This standardized approach ensures uniformity while also providing flexibility for custom implementations.

```swift
/// A module defines a paved path for creating Tuist targets and accompanying helper targets
public protocol Module {

    /// Name of the module. e.g. "CoreEtsy"
    var moduleName: String { get }

    /// Root path of the module relative to the repository root
    var rootPath: Path { get }

    /// Main target provided by this module. Usually a framework but could be any target built with `TargetBuilder`
    var mainTarget: TargetBuilder { get }

    /// An optional target defining a demo app for the module. Defaults to `.swiftUIDemoApp`. Override to ignore or specify `.uiKitDemoApp`
    var demoAppTarget: TargetBuilder? { get }

    /// An array of targets defining automated tests for this module.  Defaults to a single unit test target. Override to modify or add other test targets like `.uiTestTarget`
    var testTargets: [TargetBuilder] { get }
    /// An array of ResourceSynthesizer to be used with default `Project`
    var resourceSynthesizers: [ResourceSynthesizer] { get }
}
```

## Code Practices and Dependency Management

**How does Etsy manage dependencies and navigate the choice of architectural practices for its iOS app?**

While [VIPER](https://www.objc.io/issues/13-architecture/viper/) was a mainstay in our iOS app, we’re now gravitating towards more modular and composable architectures, especially with the growing adoption of [SwiftUI](https://developer.apple.com/xcode/swiftui/). Our framework choices revolve around common components like [UIKit](https://developer.apple.com/documentation/uikit), with some functionalities tapping into [ARKit](https://developer.apple.com/augmented-reality/) for immersive shopping experiences. In terms of external dependencies, we keep it minimal, focusing on essential frameworks like [Nuke](https://github.com/kean/Nuke) for image handling and Lottie for animations. We harness both [Swift Package Manager](https://www.swift.org/package-manager/) and `Dependencies.swift` for dependency management.

## Processes: From Development to Deployment

### Releases and Distribution

**What is the frequency of your releases internally and to production? Could you outline the process, tools, and key personnel involved in it?**

We recently transitioned from bi-weekly to weekly releases. The process is designed to automate tedious tasks while maintaining engineer involvement throughout. Before each release, engineers review their commits to ensure they align with the intended outcomes. Before branch cut, engineers verify that the code they committed is what they intend to ship (just a simple review to ensure you find everything you expect and nothing unexpected).

On release days, engineers watch our deployment graphs and analytics pipelines to ensure their features are working as expected and that the release is behaving as expected in production.

To boost agility, we encourage frequent commits to the main branch, discouraging long-running branches. Every group of pushes to `main` creates a new internal build available to all of Etsy and internal users are able to toggle on any features they want to test or verify.

Additionally, any PR has the ability to create an installable build that can be shared with a link. This allows engineers to share builds with designers and PMs of work in progress to get stakeholder feedback as fast as possible.

### Preview Driven Development

**How do you ensure rapid iteration cycles when developing new features?**

In our journey towards modularization, we have been leaning towards something called “Preview Driven Development”. As the team went into crafting modules – which were deliberately kept small, purpose-driven, and purely Swift-based – we enjoyed notably fast compile times. This speedy compilation eased up the usage of [SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode), without being held back by our legacy monolithic codebase.

We also built a UIKit preview wrapper which lets engineers wrap UIKit views right into SwiftUI Previews. So, no matter which UI technology an engineer decides to use, previews are always an option. Opting to build with previews right from the get-go means creating components that aren’t tied down to network models or real-world data. This is a game-changer, especially when working on features that need specific data to be tested –like an account with a purchase being delivered.

Preview driven development not only improves our iteration speed just by saving time on compiles and navigating in the app, it also sets us up for future success by helping us build testable code. If our architecture is set up to be previewable with arbitrarily injected data, we can also use that same data in unit tests, helping protect against future regressions.

## Conclusion

Etsy’s journey is a testament to how organizations can evolve while retaining their core strengths. Their transition to modularity, backed by Tuist, is setting the stage for a future where innovation, speed, and quality go hand in hand.
