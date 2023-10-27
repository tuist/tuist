# ``tuist``

Tuist is a command-line interface (CLI) designed to tackle the complexities of building large-scale applications for Apple platforms.

> Warning: This website represents a partial revamp of the [Tuist documentation website](https://docs.tuist.io). For any documentation not available here, we recommend visiting the old website.


## Motivation

As Xcode projects expand, **organizations may face a decline in productivity** due to several factors, including unreliable incremental builds, frequent clearing of Xcode's global cache by developers encountering issues, and fragile project configurations. To maintain rapid feature development, organizations typically explore various strategies.

Some organizations choose to bypass the compiler by abstracting the platform using JavaScript-based dynamic runtimes, such as [React Native](https://reactnative.dev/). While this approach may be effective, it [complicates access to the platform's native features](https://shopify.engineering/building-app-clip-react-native). Other organizations opt for **modularizing the codebase**, which helps establish clear boundaries, making the codebase easier to work with and improving the reliability of build times. However, the Xcode project format is not designed for modularity and results in implicit configurations that few understand and frequent conflicts. This leads to a bad bus factor, and although incremental builds may improve, developers might still frequently clear Xcode's build cache (i.e., derived data) when builds fail. To address this, some organizations choose to **abandon Xcode's build system** and adopt alternatives like [Buck](https://buck.build/) or [Bazel](https://bazel.build/). However, this comes with a [high complexity and maintenance burden](https://bazel.build/migrate/xcode) (e.g., Xcode updates might disrupt the integration with Bazel, which is ultimately a hack).

## Tuist

[Tuist](https://tuist.io) is a viable alternative that aids in surmounting these challenges while maintaining complexity and costs at an acceptable level. It considers Xcode projects as a fundamental element, ensuring resilience against future Xcode updates, and utilizes Xcode project generation to offer teams a modularization-focused declarative API. Tuist uses the project declaration to **simplify the complexities of modularization**, **optimize workflows** like build or test across various environments, and facilitate and **democratize the evolution of Xcode projects**.

## Project generation as a foundation

Xcode, its underlying build system, and the structure of Xcode projects are closely intertwined, often leading to inflexibility. This intrinsic design leaves developers with few avenues to address the inherent challenges presented by Apple. One such solution has been **project generation**, a method initially pioneered by [CocoaPods](https://cocoapods.org) to introduce dependency management into the Objective-C ecosystem.

Tuist also adopts project generation, which might suggest that this approach is its primary objective. Indeed, many development teams have turned to project generation to mitigate the long-standing issue of team collaboration-induced conflicts. But for Tuist, **project generation isn't the endgame**. Instead, it serves as a foundational tool to tackle a broader range of challenges, including:

- How can developers modify the modular structure of a project with assurance against runtime errors, ensuring it aligns with team best practices?
- What's the best way to add or remove targets from the dependency graph without worrying about the ripple effects on the graph, such as dynamically copying frameworks into bundles?
- How can developers decouple the time of tasks—like coding, building, and testing—from the overall size of the project?
- How can teams ensure the sustained health and integrity of the project, cultivating a conducive environment for developers?

Tuist offers answers to these questions, leveraging the power of project generation. It encapsulates years of insights gathered from diverse Xcode projects, positioning itself as an invaluable ally for your platform team.

## How does it work?

To get started with Tuist, all you need is to define your project using **Tuist's Domain Specific Language (DSL)**. This entails using manifest files such as `Workspace.swift` or `Project.swift`. If you've worked with the Swift Package Manager before, the approach is very similar.

Once you've defined your project, Tuist offers various workflows to manage and interact with it:

- **Generate:** This is a foundational workflow. Use it to create an Xcode project that's compatible with Xcode.
- **Build:** This workflow not only generates the Xcode project but also employs xcodebuild to compile it.
- **Test:** Operating much like the build workflow, this not only generates the Xcode project but utilizes xcodebuild to test it.

Additionally, as detailed in <doc:Tuist-Cloud---Intro>, Tuist offers a suite of optimizations. These include **target-focused project generation**, the ability to swap out targets and dependencies with their **binary** equivalents, and ensuring build and test incrementality across different environments (e.g., local machine vs. CI). Plus, it provides actionable insights to guide teams in making informed choices.

> Tip: Tuist's optimizations and insights stem from the knowledge gained from your project's manifest files. To ensure teams remain productive, data-backed decisions are essential—something Xcode doesn't offer. As a result, teams often operate without clear insights, unsure if their choices benefit the project.

## Frequently asked questions

### How does Tuist compare to...

##### Swift Package Manager

While the Swift Package Manager (SPM) primarily focuses on dependencies, Tuist offers a different approach. With Tuist, you don't just define packages for SPM integration; you shape your projects using familiar concepts like projects, workspaces, targets, and schemes.

##### XcodeGen

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is a dedicated project generator designed to reduce conflicts in collaborative Xcode projects and simplify some complexities of Xcode's internal workings. However, projects are defined using serializable formats like [YAML](https://yaml.org/). Unlike Swift, this doesn't allow developers to build upon abstractions or checks without incorporating additional tools. While XcodeGen does offer a way to map dependencies to an internal representation for validation and optimization, it still exposes developers to the nuances of Xcode. This might make XcodeGen a suitable foundation for [building tools](https://github.com/MobileNativeFoundation/rules_xcodeproj), as seen in the Bazel community, but it's not optimal for inclusive project evolution that aims to maintain a healthy and productive environment.

##### Bazel

[Bazel](https://bazel.build) is an advanced build system renowned for its remote caching features, gaining popularity within the Swift community primarily for this capability. However, given the limited extensibility of Xcode and its build system, substituting it with Bazel's system demands significant effort and maintenance. Only a few companies with abundant resources can bear this overhead, as evident from the select list of firms investing heavily to integrate Bazel with Xcode. Interestingly, the community created a [tool](https://github.com/MobileNativeFoundation/rules_xcodeproj) that employs Bazel's XcodeGen to generate an Xcode project. This results in a convoluted chain of conversions: from Bazel files to XcodeGen YAML and finally to Xcode Projects. Such layered indirection often complicates troubleshooting, making issues more challenging to diagnose and resolve.

### What if the tool is deprecated at some point?

Rest assured, if any issues arise, you can simply add the Xcode projects and workspaces to the version control system to resolve them. One of Tuist's core design principles is to align closely with Xcode and industry standards. Notably, the generated projects are independent, with no ties or references to Tuist.

### Should I gitignore my projects?

The choice is yours. By adding .xcodeproj and .xcworkspace files to your .gitignore, you can avoid many git conflicts. We suggest initially migrating the project to Tuist. After ensuring everything functions smoothly, guide your team on using tuist generate before they start working on a project. Once this becomes a routine, you can safely add those projects to .gitignore without any issues.

## Topics

### Tuist

- <doc:Tuist-Tutorial>

### Tuist Cloud

- <doc:Tuist-Cloud---What>
- <doc:Tuist-Cloud---Command-Line-Interface>
- <doc:Tuist-Cloud-Tutorial>
