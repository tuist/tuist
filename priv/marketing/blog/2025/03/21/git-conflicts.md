---
title: "Strategies to avoid merge conflicts in Xcode Projects"
category: "learn"
tags: ["pbxproj file", "file references", "xcodeproj file", "conflicts", "merge tool", "Xcode"]
excerpt: "Learn why Xcode’s project.pbxproj triggers Git conflicts and how solutions like workspaces, SwiftPM or buildable groups can help developers reduce frustration in collaborative projects."
author: pepicrft
---

If you’ve collaborated with other developers on an Xcode project, you’ve likely encountered frequent Git conflicts—more so than in any other development ecosystem. This can be incredibly frustrating, especially if you’re unfamiliar with the `project.pbxproj` file, where these conflicts typically arise. 

In this post, we’ll explore why these conflicts occur in Xcode projects, examine the various solutions that have emerged to address them, and provide actionable steps you can take to eliminate this common source of frustration for developers.

## Why do conflicts exist?

Xcode projects are a directory with the extension `.xcodeproj` that contain a file `project.pbxproj`.
Back when Apple introduced Xcode in 2023 as part of Mac OS X 10.3,
projects were small, 
and collaboration following trunk-based development was not that common as it is today.
For context,
Linus Torvalds released Git in 2005,
and GitHub was founded in 2008.
So at the time, conflicts did not exist,
and Apple decided to create a monolithic file where all the project description would be stored, `project.pbxproj`.
The `project.pbxproj` is a property list file that was not designed to be edited directly.
Instead, the changes are done using Xcode's UI, and Xcode is the one responsible for translating those changes into the `project.pbxproj` file.
Group and file references (for example, to reference Swift files) are among the building blocks
that represent the hierarchical structure of the project. For example:
```
/* Begin PBXFileReference section */
		6CA84C022D8DAA1200086F24 /* Framework.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Framework.framework; sourceTree = BUILT_PRODUCTS_DIR; };
		6CA84C0A2D8DAA1200086F24 /* FrameworkTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = FrameworkTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */
```

These lines update whenever a file is added, removed, or relocated in the project hierarchy—common actions in a pull request (PR). This frequent updating is a primary driver of merge conflicts.

To address this, Apple introduced workspaces in [Xcode 4](https://developer.apple.com/xcode/) in 2011, enabling teams to split targets across multiple projects. The idea was that distributing `project.pbxproj` files across smaller projects would reduce conflicts. While no hard data confirms their adoption rate, workspaces likely didn’t gain the traction Apple anticipated.

In September 2016, with the release of [Xcode 8](https://developer.apple.com/documentation/xcode-release-notes/xcode-8-release-notes), Apple added comments to project.pbxproj files (e.g., `/* Framework.framework */`). This made conflicts easier to resolve by providing context, compared to cryptic identifiers like `6CA84C022D8DAA1200086F24`. Yet, in 2025, teams still grapple with these issues—not because solutions are lacking, but because awareness or implementation lags.

Let’s dive into practical strategies to mitigate these conflicts.

## Splitting a monolith into multiple projects

Since 2011, one effective approach has been organizing your workspace into multiple projects. For instance, you could create a project per domain or feature, each containing its source files, tests, and a demo app. Check out [Tuist’s modular architecture](https://docs.tuist.io/guides/develop/projects/tma-architecture) guide for inspiration on structuring your projects efficiently.

While this reduces conflicts by distributing the dependency graph, it may slightly increase Xcode’s indexing and build times due to the added complexity of resolving inter-project dependencies. You’ll also need to explicitly define these dependencies to ensure Xcode’s build system links products correctly.

## Project generation

Tools like [Tuist](https://docs.tuist.dev) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) ([How DoorDash uses XcodeGen to eliminate project merge conflicts](https://careersatdoordash.com/blog/how-doordash-uses-xcodegen-to-eliminate-project-merge-conflicts/)) offer an alternative by introducing domain-specific languages (DSLs) in Swift or YAML to define projects. Instead of listing every file (e.g., one per line), they use wildcard patterns like `/Sources/**/*.swift`, reducing the file’s churn and thus the likelihood of conflicts.

The popularity of project generation stems from this pain point. Tuist, for example, not only minimizes conflicts but also simplifies modularization and optimizes workflows. If conflicts are your only gripe, project generation might be overkill. But if modularization complexity or slow workflows also frustrate you, tools like Tuist are worth exploring.

## Using SwiftPM as a project manager

In 2015, Apple introduced the [Swift Package Manager (SwiftPM)](https://www.swift.org/package-manager/), initially a dependency management tool. By September 2016, with its integration into Xcode, developers began using it to link local and external dependencies. What started as a dependency manager evolved into a de facto project manager for many.

Frustrated by `project.pbxproj` conflicts and modularization woes, developers migrated their project graphs to SwiftPM. Like project generation, SwiftPM uses wildcard patterns (e.g., `Sources/**/*.swift`), lowering conflict risks. However, this shift trades one annoyance for another: Xcode can become sluggish, with tiny graph changes triggering slow, asynchronous processes—or worse, leaving your project in an inconsistent state requiring a clean of derived data.

## Synchronized groups (buildable folders) in Xcode 16

In 2024, Apple introduced synchronized groups in [Xcode 16](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes), akin to wildcard functionality. These groups reference a directory, and Xcode syncs all files within it, allowing exceptions (e.g., excluding a file or tweaking configurations).

In Xcode, these are called “folders.” To convert a group, right-click it and select “Convert to Folder”:

<img alt="An image that shows the right click menu on a group with the option to convert to folder" width="400" src="/marketing/images/blog/2025/03/21/convert-to-folder.jpeg"/>

Before converting, use a tool like [XcodeGroupSync](https://github.com/qonto/XcodeGroupSync) to align your groups with the file system. Skipping this step risks compilation or runtime errors from missing files or misconfigurations. This feature is a low-effort, high-return investment for teams.

## Closing words

Source control merge conflicts in Xcode projects, driven by the project file, have plagued developers for years. Fortunately, you have multiple options to tackle them: splitting projects, adopting project generation tools like Tuist or XcodeGen, leveraging SwiftPM, or using synchronized groups in Xcode 16. Each solution has trade-offs, but they all aim to streamline collaboration and reduce frustration.

Start small—experiment with synchronized groups or a multi-project workspace—and scale up based on your team’s needs. By addressing this pain point, you’ll boost productivity and make your development process smoother. Have a favorite solution? Share it with us on [Mastodon](https://fosstodon.org/@tuist)!
