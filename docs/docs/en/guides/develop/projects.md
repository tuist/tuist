---
title: Projects
titleTemplate: ":title | Develop | Tuist"
description: Learn about Tuist's DSL for defining Xcode projects.
---

# Projects

Tuist Projects is a viable alternative that helps to overcome these challenges while keeping complexity and costs at an acceptable level. It considers Xcode projects as a fundamental element, ensuring resilience against future Xcode updates, and leverages Xcode project generation to provide teams with a modularization-focused declarative API. Tuist uses the project declaration to simplify the complexities of modularization**, optimize workflows like build or test across various environments, and facilitate and democratize the evolution of Xcode projects.

## How does it work?

To get started with Tuist Projects, all you need is to define your project using **Tuist's Domain Specific Language (DSL)**. This entails using manifest files such as `Workspace.swift` or `Project.swift`. If you've worked with the Swift Package Manager before, the approach is very similar.

Once you've defined your project, Tuist offers various workflows to manage and interact with it:

- **Generate:** This is a foundational workflow. Use it to create an Xcode project that's compatible with Xcode.
- **[Build](/guides/develop/build):** This workflow not only generates the Xcode project but also employs `xcodebuild` to compile it.
- **[Test](/guides/develop/test):** Operating much like the build workflow, this not only generates the Xcode project but utilizes `xcodebuild` to test it.

## Challenges with Xcode projects

As Xcode projects grow, **organizations may face a decline in productivity** due to several factors, including unreliable incremental builds, frequent clearing of Xcode's global cache by developers encountering issues, and fragile project configurations. To maintain rapid feature development, organizations typically explore various strategies.

Some organizations choose to bypass the compiler by abstracting the platform using JavaScript-based dynamic runtimes, such as [React Native](https://reactnative.dev/). While this approach may be effective, it [complicates access to the platform's native features](https://shopify.engineering/building-app-clip-react-native). Other organizations opt for **modularizing the codebase**, which helps establish clear boundaries, making the codebase easier to work with and improving the reliability of build times. However, the Xcode project format is not designed for modularity and results in implicit configurations that few understand and frequent conflicts. This leads to a bad bus factor, and although incremental builds may improve, developers might still frequently clear Xcode's build cache (i.e., derived data) when builds fail. To address this, some organizations choose to **abandon Xcode's build system** and adopt alternatives like [Buck](https://buck.build/) or [Bazel](https://bazel.build/). However, this comes with a [high complexity and maintenance burden](https://bazel.build/migrate/xcode).


## Alternatives

### Swift Package Manager

While the Swift Package Manager (SPM) primarily focuses on dependencies, Tuist offers a different approach. With Tuist, you don't just define packages for SPM integration; you shape your projects using familiar concepts like projects, workspaces, targets, and schemes.

### XcodeGen

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is a dedicated project generator designed to reduce conflicts in collaborative Xcode projects and simplify some complexities of Xcode's internal workings. However, projects are defined using serializable formats like [YAML](https://yaml.org/). Unlike Swift, this doesn't allow developers to build upon abstractions or checks without incorporating additional tools. While XcodeGen does offer a way to map dependencies to an internal representation for validation and optimization, it still exposes developers to the nuances of Xcode. This might make XcodeGen a suitable foundation for [building tools](https://github.com/MobileNativeFoundation/rules_xcodeproj), as seen in the Bazel community, but it's not optimal for inclusive project evolution that aims to maintain a healthy and productive environment.

### Bazel

[Bazel](https://bazel.build) is an advanced build system renowned for its remote caching features, gaining popularity within the Swift community primarily for this capability. However, given the limited extensibility of Xcode and its build system, substituting it with Bazel's system demands significant effort and maintenance. Only a few companies with abundant resources can bear this overhead, as evident from the select list of firms investing heavily to integrate Bazel with Xcode. Interestingly, the community created a [tool](https://github.com/MobileNativeFoundation/rules_xcodeproj) that employs Bazel's XcodeGen to generate an Xcode project. This results in a convoluted chain of conversions: from Bazel files to XcodeGen YAML and finally to Xcode Projects. Such layered indirection often complicates troubleshooting, making issues more challenging to diagnose and resolve.