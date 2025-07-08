---
title: "Glovo’s Large-Scale App Development: An In-Depth Look"
category: "community"
tags: ['Glovo', 'Development Tools', 'Modular Architecture', 'Team structure', 'Dependency Injection']
type: interview
excerpt: "Glovo's app development focuses on modular architecture, efficient processes, and a robust team to ensure a top-tier digital experience."
interviewee_name: David Cacenabes
interviewee_role: "Senior iOS engineer at Glovo"
interviewee_url: https://www.linkedin.com/in/cvdavid/
interviewee_avatar: /images/interviewees/david-cacenabes.jpeg
---

**This interview has been edited by [María José Salmerón](https://www.linkedin.com/in/mariajosesalmeron/)**

In today’s fast-paced digital ecosystem, maintaining a top-tier app requires more than just a great user interface. For companies like [Glovo](https://glovoapp.com/), the magic lies in a blend of innovative architecture, streamlined processes, and a dedicated team. In this interview, we look into the intricate world of Glovo’s iOS development. From modular project structures to efficient testing strategies, we will discover how one of the world’s leading on-demand delivery services crafts its digital experience.

## Organizational Overview

#### How is the iOS development team at Glovo structured?

At Glovo we have a team of over **30 iOS engineers**. These engineers collaborate within multi-disciplinary teams, encompassing UX, [Android](https://www.android.com), and [iOS](https://en.wikipedia.org/wiki/IOS) expertise. We have two user facing apps: **Customer** and **Courier**. While most teams specialize in just one of these apps, the **Platform team** is an exception as we not only contribute to all apps and libraries, but we also develop tools for developers and oversee the maintenance of our CI infrastructure.

## Development Environment: Balancing Freedom and Consistency

#### What tools, apart from Xcode, do the developers at Glovo rely on?

Our iOS developers utilize an array of tools including [Fastlane](https://github.com/fastlane/fastlane), [Xcodegen](https://github.com/yonaskolb/XcodeGen), [Swiftgen](https://github.com/SwiftGen/SwiftGen), [Sourcery](https://github.com/krzysztofzablocki/Sourcery), [xcodes](https://github.com/XcodesOrg/xcodes), and [Cocoapods](https://github.com/CocoaPods/CocoaPods). These tools are provisioned through methods such as [Homebrew](https://brew.sh) and scripts that engineers can run to get all the tooling installed and set up.

For **Ruby**, we suggest engineers utilize environment files such as `.rbenv` or `.tool-versions`. However, developers are welcome to configure their setup as they prefer and can use alternative runtime version managers like [asdf](https://asdf-vm.com).

Regarding [Xcode](https://en.wikipedia.org/wiki/Xcode), while we don't mandate a particular version for our engineers, we do have an `.xcode-version` file for CI purposes. We advise engineers to adhere to this version to take advantage of cache reuse from CI builds, but it's not a strict requirement at this time.

## Modular Project Architecture

#### Could you elaborate on Glovo's modular project architecture and its foundations?

Our focus is on a modular architecture, prioritizing a flat module graph to reduce build times. This architecture aids in parallel module building and lessens the code rebuild frequency when module changes occur. Our modules come in different types: `Implementation`, `API`, `Shared Types`, `InDebt`, and `Testing`. Each has its purpose and strict relationship rules, ensuring consistency across the project. The compliance of these rules is validated during build time.


Further details on this topic can be found [in a presentation](https://www.droidcon.com/2022/11/15/modularization-flatten-your-graph-and-get-the-real-benefits/) given by my teammate, [Josef Raska](https://twitter.com/josef_raska), at [Droidcon](https://www.droidcon.com).

#### How does the iOS architecture compare with Android, and how is consistency maintained?

The overarching architecture is mirrored for both platforms. Although the tools differ (a Gradle plugin for Android and a Swift Package for iOS), both are rigorously tested to guarantee consistent behavior.

#### Who can modify the architecture, like adding new modules?

Engineers are welcome to propose new modules, as long as they adhere to our guidelines and there's a clear rationale for the addition.

Through extensive research, we've assessed the impact of adding a module on both iOS and Android platforms. Factors like its effect on app launch times, required storage on a computer, and feedback from developers (for instance, how adding more modules can slow down Android Studio Sync) were considered. Our findings revealed that introducing modules isn't without costs. Developers should carefully weigh the need to separate specific code into its own module. As a rule of thumb, **we steer clear of very small modules, typically those with less than 1,000 lines of code.**

When suggesting a new module type, it's essential to undergo a detailed peer review. We have well-defined beliefs about module types, backed by solid reasoning. Any addition of a new type demands peer validation and a robust justification. Since we started our modularization efforts, we've incorporated two new types: `InDebt` and `Testing`. We also have a dedicated Slack channel to foster discussions about modularization, ensuring our architectural direction remains consistent.

#### What challenges come with maintaining and evolving this modular architecture?

One of our main challenges is to maintain consistent architecture across various apps and platforms while also ensuring a positive developer experience. To achieve this, we use internal tools to ensure module consistency. Additionally, we employ a mix of custom and third-party solutions to monitor build times and prevent setbacks. On the Android side, we trust [Gradle Enterprise](https://gradle.com). Meanwhile, for iOS, we've developed a unique tool largely influenced by [Spotify's XCMetrics](https://xcmetrics.io/). This tool processes Xcode build logs and dispatches comprehensive build data to our analytics system.

## Code Management

#### Which code architectures and design patterns are predominant at Glovo?

Although many teams adopt [MVVM](https://en.wikipedia.org/wiki/Model–view–viewmodel) + Coordinators, we encourage teams to choose architectures that best fit their needs. However, some rules do apply across teams. For instance, in the Customer app, all teams utilize [Needle](https://github.com/uber/needle) for dependency injection.

#### Which platform frameworks are frequently utilized?

[UIKit](https://developer.apple.com/documentation/uikit) and [Core Location](https://developer.apple.com/documentation/corelocation) are our mainstays, with occasional use of [Core Data](https://developer.apple.com/documentation/coredata/).

#### How does Glovo manage external dependencies?

Our dependencies are currently managed through [Cocoapods](https://cocoapods.org). However, we've implemented a strict vetting process for adding new external dependencies. Previously, there were fewer restrictions on incorporating new external dependencies, but after examining numerous post-incident reviews, we found that many issues in production were traced back to these external sources. These not only affected production but also worsened the developer experience. For instance, significant changes in the APIs of [Quick](https://github.com/Quick/Quick) and [Nimble](https://github.com/Quick/nimble) meant we had to allocate substantial resources to keep our test suites up to date. We’ve finally started using [XCTest](https://developer.apple.com/documentation/xctest) directly to streamline the process.

Now, **before adding a new dependency, we conduct a thorough assessment**. This includes checking the code quality, gauging its impact on build time and binary size, and assessing its overall reliability. Such experiences have underscored the importance of a shift in our engineering mindset regarding external dependencies.

> We've come to view anything we incorporate into our app as an extension of our own codebase because it affects both our development process and performance in production.

## Processes and Tools: Optimizing Release Cycles and Feature Distribution

#### Could you detail the release schedule and feature distribution practices at Glovo?

We’ve streamlined our release process to be weekly which involves release branch creation,  internal beta shipping, submission for review, phased rollouts, and subsequent full releases. Our current release pipelines are built on top of [Jenkins](https://www.jenkins.io) with [Groovy](https://groovy-lang.org) scripting language, but we're transitioning to [Github Actions](https://docs.github.com/en/actions).

Internal alpha builds are shipped upon every PR merge into `develop`, and **beta versions are continuously shipped for 3000+ employees**, ensuring regular internal testing and feedback. This strategy, coupled with incentivized employee beta usage, aids in early identification and swift rectification of potential issues.

[Here is a talk](https://youtu.be/QIprGMU2S20) that, although a bit old, goes deeper in our release process.

#### How is the rapid iteration of new features ensured?

**"Building less to iterate faster" encapsulates our approach.** We leverage modularization and tooling to allow engineers to work with independent, module-specific example apps, minimize build times, and facilitate efficient development through precompiled dependencies. This ensures that we don’t waste time waiting for libraries to be built, minimizing not only incremental builds but also clean ones.

#### How is the testing strategy formulated to align with the development and release cycles?

Developers typically run specific module or suite tests locally. However, CI presents the unique challenge of ensuring thorough testing while keeping a rapid feedback loop.

To address this, many organizations run all test suites in their CI, but that leads to delayed feedback. In contrast, **we developed an internal solution which we refer to as 'selective test running'.** This tool identifies changed modules, analyzes our dependency tree for all related modules, and then exclusively tests them. When combined with precompiling dependencies, **we've seen a 40% reduction in CI time**, which is a significant boost for a modularized codebase.

In addition to this, **we've automated end-to-end UI test executions against local servers providing mocked responses.** This not only boosts our confidence but also allows a release cycle free from manual intervention.

## Closing Thoughts

[Glovo](https://glovoapp.com) demonstrates a multifaceted approach to managing a large-scale development environment, striking a balance between structure and autonomy, thoroughness, and agility. Using a carefully crafted architecture and a meticulously designed development and release cycle, they manage to navigate the complexities that emerge in large-scale development settings. For organizations scaling up, adopting a similarly strategic and tool-facilitated approach to structure, development, and release processes may well pave the way for sustainable growth and development efficiency.
