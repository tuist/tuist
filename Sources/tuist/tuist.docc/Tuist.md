# ``tuist``

Tuist is a command-line interface (CLI) designed to tackle the complexities of building large-scale applications for Apple platforms.

> Warning: This website represents a partial revamp of the [Tuist documentation website](https://docs.tuist.io). For any documentation not available here, we recommend visiting the old website.


## Motivation

As Xcode projects expand, **organizations may face a decline in productivity** due to several factors, including unreliable incremental builds, frequent clearing of Xcode's global cache by developers encountering issues, and fragile project configurations. To maintain rapid feature development, organizations typically explore various strategies.

Some organizations choose to bypass the compiler by abstracting the platform using JavaScript-based dynamic runtimes, such as [React Native](https://reactnative.dev/). While this approach may be effective, it [complicates access to the platform's native features](https://shopify.engineering/building-app-clip-react-native). Other organizations opt for **modularizing the codebase**, which helps establish clear boundaries, making the codebase easier to work with and improving the reliability of build times. However, the Xcode project format is not designed for modularity and results in implicit configurations that few understand and frequent conflicts. This leads to a bad bus factor, and although incremental builds may improve, developers might still frequently clear Xcode's build cache (i.e., derived data) when builds fail. To address this, some organizations choose to **abandon Xcode's build system** and adopt alternatives like [Buck](https://buck.build/) or [Bazel](https://bazel.build/). However, this comes with a [high complexity and maintenance burden](https://bazel.build/migrate/xcode) (e.g., Xcode updates might disrupt the integration with Bazel, which is ultimately a hack).

## Tuist

[Tuist](https://tuist.io) is a viable alternative that aids in surmounting these challenges while maintaining complexity and costs at an acceptable level. It considers Xcode projects as a fundamental element, ensuring resilience against future Xcode updates, and utilizes Xcode project generation to offer teams a modularization-focused declarative API. Tuist uses the project declaration to **simplify the complexities of modularization**, **optimize workflows** like build or test across various environments, and facilitate and **democratize the evolution of Xcode projects**.

## Project generation as a foundation

Xcode, its build system, and Xcode projects are strongly coupled and lack flexibility. This leaves the community with limited options to overcome the challenges that Apple's design presents. One of the options is **project generation**, that was first used by [CocoaPods](https://cocoapods.org) to bring dependency management to the Objective-C ecosystem. 

Tuist leverages project generation too, something that might make you think that we have project generation as a goal. Many teams in fact resort to project generation to overcome a challenge that has persisted for years, the proneness to conflicts when working in teams. However, project generation for Tuist is a means to an end. It's a foundation to solve challenges that go beyond project generation. Here's a non-exhaustive list of them:

- How can I modify the project modular structure with the confidence that it won't lead to runtime errors and that adheres to my team's best practices?
- How can I add/remove targets from the graph without having to think about the cascading effects my changes have on the graph (e.g. copying dynamic frameworks into bundles)?
- How can I decouple productivity coding, building, and testing, from the size of the project? 
- How can I make sure my project and the workflows remain healthy fostering an environment in which developers want to work?

Tuist is a tool that provides answers to those questions by leveraging projec generation. It codifies years of experience working in a large range of Xcode project types, and is the excellent copilot for your platform team.

> Tip: Extensible tooling would have prevented us from resorting to project generation to tackle the challenges, but Xcode doesn't seem to be moving in that direction.

## How does it work

All Tuist needs from you is your project defined using Tuist's DSL. You define your projects using manifest files like **Workspace.swift** or **Project.swift**. If you are familiar with the Swift Package Manager, the concept is identical.

Once your project is defined, Tuist provides different workflows to interact with your projects:

- **Generate:** This is a cornerstone workflow. You use it to generate an Xcode project that you can use with Xcode. 
- **Build:** This workflow generates the Xcode project and runs `xcodebuild` to build the project.
- **Test:** Similarly to build, it generates the Xcode project but in this case it uses `xcodebuild` to test the project.

Tuist also provides as part of <doc:Tuist-Cloud---Intro> a set of **optimizations**, like project generation with a focus on a target, replacement of targets and dependencies with their binary counterpart, or build and test incrementality across environments (e.g., local and CI), and **actionable insights** to help teams make informed decisions. 

> Tip: Tuist optimizations and insights are possible thanks to the knowledge that we have on your projects graph through your declaration in manifest files. We believe for teams to remain productive, we need data to back decisions, and that's unfortunately something that Xcode doesn't provide so teams often move blindly without being aware of where the time is being spent or with the confidence that the decisions that they are making are positive for the project.

## Frequently asked questions

### How does Tuist compare to...

##### Swift Package Manager

Although there are similarities between both tools, the Swift Package Manager (SPM)'s main focus is on dependencies. With Tuist, instead of defining packages that SPM integrates into your projects, you define your projects using concepts you are already familiar with: projects, workspaces, targets, and schemes.

##### XcodeGen

XcodeGen is a pure project generator that helps mitigate conflicts when collaborating in an Xcode project and abstracts away some intricacies of Xcode projects' internals. However, projects' definition is done through serializable formats like YAML, which unilke Swift, developers can't build their abstracions or checks upon unless they implement additional tooling. Moreover, when it comes to mapping dependencies to an internal representation that can be validated and optimized, their implementation still presents developers with the Xcode intricacies and requires them to understand some Xcode internals. The above makes it a good candidate as a foundation to build tools upon, like the Bazel community does, but not that ideal if you want everyone to take part of evolving a project and being assisted in evolving the projects to keep the environment healthy and productive.

##### Bazel

Bazel is a very sophisticated build system with support for remote caching. It popularized among the Swift community due to its caching capabilities. However, since Xcode and its build system is not much extensible, the replacement of the build system with Bazel's and their maintenance requires a huge burden that only few companies can afford. This is something that can be seen from the list of companies that are using it and that coincidentally are pouring a lot of resources into making Bazel work with Xcode. Fun fact, the community built a tool that uses Bazel XcodeGen to generate an Xcode project, so the amount of indirection is bizarre: Bazel files > XcodeGen YAML > Xcode Projects. Indirection is usually a source of nightmares when problems arise and need to be debugged and fixed.


### What if the tool is deprecated at some point?

There's nothing to worry about, because if that happens, you can just add the Xcode projects and workspaces to the version control system and problem solved. One of Tuist's design principles is **staying as close as possible to Xcode and industry standards.** Generated projects have no dependency nor reference to Tuist whatsoever.

### Should I gitignore my projects?

This is really up to you. If you add the `.xcodeproj` and `.xcworkspace` files to your `.gitignore` file you'll save tons of painful git conflicts. Our recommendation is that you first migrate the project to Tuist, and once everything is up and running, educate the developers in your team on running tuist generate when they plan to work on a project. Once they build the habit, you should be able to .gitignore those projects with no impact at all.

## Topics

### Tuist

- <doc:Tuist-Tutorial>

### Tuist Cloud

- <doc:Tuist-Cloud---What>
- <doc:Tuist-Cloud---Command-Line-Interface>
- <doc:Tuist-Cloud-Tutorial>
