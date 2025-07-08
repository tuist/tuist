---
title: "The Evolution of iOS Development and the Role of Tuist"
product: "releases"
tags: ["Tuist", "Xcode", "iOS Development", "Scaling", "Swift Package Manager", "CocoaPods", "Build Systems", "Modularization"]
excerpt: "Tuist, born in 2017, addresses challenges in scaling Xcode projects. Despite new tools like the Swift Package Manager, the need for Tuist persists."
author: pepicrft
---

# Tuist's Role in the Changing Landscape of iOS Development

Tuist was conceived in 2017 to address the growing complexities of iOS development. The journey to modularize Xcode projects was about crafting a maintainable codebase accessible to multiple teams. However, **using only the primitive of Xcode projects made the task daunting**. We yearned for an extensible build system to tackle the challenges we encountered, but that wasn't the reality then. Fast forward to today: while the landscape has transformed with innovations like [SwiftUI](https://developer.apple.com/xcode/swiftui/), [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/), and various build tools — and even an official solution from Apple ([Swift Package Manager](https://www.swift.org/package-manager/)) for Xcode project dependencies — the core challenges persist. Alarmingly, developers often harbor the hope that official tools will solve all issues, oblivious to the complications they introduce. This post aims to provide clarity on the current state, speculate on the direction Apple might have chosen, and assert why Tuist remains pertinent.

## Xcode Projects: The Beginning

In 2003, when Apple introduced the first iteration of Xcode, projects bore little resemblance to today's structure. Often comprising just a single target for [macOS](https://en.wikipedia.org/wiki/MacOS), these projects were devoid of intricate dependencies and didn't facilitate code interoperability between diverse languages. Interestingly, [Git](https://en.wikipedia.org/wiki/Git), a now indispensable tool, wasn't even around; [Linus Torvalds](https://en.wikipedia.org/wiki/Linus_Torvalds) introduced it in 2005. However, as the ecosystem burgeoned — spanning multiple platforms and an expanding user base — both applications and the projects underpinning them grew in complexity. Apple had to refine Xcode projects, the foundational unit that Xcode interacts with.

For those unfamiliar, Xcode projects consist of smaller, pivotal components, with the `project.pbxproj` file being paramount. This PropertyList-encoded file remains concealed from the developer, with Apple envisioning all interactions through Xcode's UI. Hence, any modification in the UI corresponds to changes in the `project.pbxproj` file. Regrettably, the adoption of a static build system has often been the root cause of issues developers would later grapple with.

## The Shift: Monolithic to Multi-project Workspaces

It became evident that `.pbxproj` files weren't designed for collaboration. To combat this, Apple encouraged developers to fragment their monolithic projects. The primary motivation was to reduce issues like recurring Git conflicts, inherent to a monolithic file structure. March 2011 marked a significant change with Xcode 4 introducing [**Workspaces**](https://developer.apple.com/library/archive/featuredarticles/XcodeConcepts/Concept-Workspace.html). Although a promising concept on paper, its real-world application was fraught with complications. Workspaces inevitably resulted in a **distributed target graph sprawled across multiple projects**. Consequently, a `.pbxproj` from one project might reference a target defined in another. Git conflicts in cryptic `.pbxproj` files became a frequent developer annoyance, often leading to broken projects. In tandem, Apple launched a feature for **implicit dependency detection**. Although intended to aid developers, this added layer of abstraction complicated scalability. Optimizing and ensuring correctness is more straightforward with an explicit graph. Apple tried striking **a balance between developer convenience and scalability but seemed to favor the former**, inadvertently complicating the latter. Back then, the ramifications were limited, but the scenario has drastically changed.

> Apple introduced comments in `.pbxproj` files in Xcode 10 (September 2018) as part of a broader effort to improve the diffing and merging experience with version control systems, notably Git.

## Code Sharing Across Xcode Projects

2011 was also significant for another reason: the birth of [CocoaPods](https://cocoapods.org/). As the broader tech community embraced package managers to nurture ecosystems, Xcode lagged. [Eloy Durán and Fabio Pelosin](https://en.wikipedia.org/wiki/CocoaPods) tackled this challenge head-on. Due to the inextensibility of Xcode's build system, their solution comprised a blend of project generation and `.xcconfig` files. This approach integrated a new Xcode project into a workspace containing all dependencies. **Given Apple's constraints, their project generation strategy was innovative**. Their pioneering efforts greatly benefited the Swift and Objective-C communities and laid a foundation for tools like Tuist.

## Swift Package Manager: The Game Changer of 2016

**Five years post-CocoaPods**, Apple unveiled their official package manager: [the Swift Package Manager (SPM)](https://www.swift.org/package-manager/). The initial response was euphoric, but **it took until 2019 for Apple to integrate it into Xcode**. As CocoaPods usage declined, a migration wave toward SPM began. Some even envisaged SPM as a potential project manager. The community's excitement soon manifested as tools built around SPM. However, **leveraging a tool beyond its intended purpose often leads to unintended complexities.**

## Build, launch, and generation time

Until the Swift Package Manager's integration, there were two stages in development: **generation and build time.** Generation time occurred before opening an Xcode project. This was the workaround for Xcode's inextensible build system. Tools like `bundle exec pod install` or `tuist generate` output something ready for opening and compiling. When Apple integrated the Swift Package Manager, they introduced a new phase: **launch time**. This means that upon launching a project, it might not be ready for interaction.

The integration, even after three years of development, had overlooked implications:

- Cleaning derived data purges resolved dependencies, making projects unusable.
- Failure in resolving dependencies creates issues due to Xcode's private usage of the Swift Package Manager.
- And more problems arise with Xcode's implicit dependency resolution and the introduction of more private integrations.

While using the Swift Package Manager as a project manager sounds ideal, it's not feasible for large-scale apps. Many challenges can be addressed at the UI level, but the ones that surface at scale are **neither addressed by Apple, neither made addressable by the community.**

## What could Apple have done differently?

There's no silver bullet solution for this, but **Swift Package Manager could have been an excellent inflection point to start building a more extensible build system.** Imagine how amazing that would have been for the community. Organizations like [Spotify](https://spotify.com) or [Lyft](https://lyft.com) that need a more sophisticated build system like [Bazel](https://bazel.build/) wouldn't have to resort to project generation to integrate Bazel into Xcode. We could have used the same foundation to introduce optimizations and tools useful at scale, such as telemetry or binary caching. Even Swift Package Manager could have been developed by those who made [CocoaPods](https://cocoapods.org) possible if the right APIs were provided. Designing tooling that targets a wide range of users is very challenging, so they could have adopted a mindset that we support 90% of the users with our default and expose APIs for developers to help with the rest. But what are they already doing with Swift Build Tools?
Kind of, but the integration between Xcode and SPM remains closed. Any communication that happens there is private and not exposed to developers.

## Why is Tuist still relevant?

Because we didn't have APIs, we had to resort to project generation. *Would it have been better if we had APIs?* Hell yeah! *Who wants an extra phase when everything can happen at build time?* But we had to resort to the same API CocoaPods used back then. This is extremely frustrating. We spend our days trying to help organizations that find themselves between "I want to use the cool stuff from Apple even if I know it's not ready" and "I have to use Tuist, but I have to make sure you guys don't take me from the cool stuff everyone is talking about." It is sometimes frustrating, but we'll further work on the problem space as much as possible. **Being able to open a project and start working on it without compiling pieces that other developers have already compiled or having data to make informed decisions is the way to work at scale**, and Apple is not interested in that—at least today. So when people wonder why they should use Tuist, our common answer is if you want to remain productive and not have to deal with the issues that Apple's tooling brings, you should use Tuist.
