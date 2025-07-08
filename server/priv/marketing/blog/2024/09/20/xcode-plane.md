---
title: "Shall the Xcode plane land?"
category: "learn"
tags: ["Releases"]
excerpt: "Xcode becomes more powerful yet more unreliable as capabilities are added and projects grow. We explore the challenges of scaling development in Xcode and share some thoughts on how Apple could improve the developer experience."
author: pepicrft
---

You have an idea for an app—perhaps something for the exciting new [visionOS platform](https://developer.apple.com/visionos/). You open [Xcode](https://developer.apple.com/xcode/), the official development environment for Apple platforms, create a new project, hit run, and voilà, a "Hello World" is up and running in the simulator. That initial moment, from conceiving an idea to seeing it come to life, is crucial in keeping your motivation high. Apple has done a fantastic job making that process swift and seamless. But that first line of Swift code marks the beginning of a much longer journey, and as your app grows, the initial burst of enthusiasm can quickly fade as the complexity of development increases.

At Tuist, we've engaged with numerous developers and companies about their experiences scaling app development, particularly in the context of Xcode and its projects. These conversations have highlighted common challenges and patterns that arise as projects grow. While we've shared insights within our [Slack community](https://slack.tuist.io), we believe it's important to reach a broader audience. Our goal is to equip developers and organizations with the knowledge to identify these challenges early and to provide a vision for how Apple could enhance the developer experience. But first, let's explore the topic of scaling.

## Scaling

It's true that if you're a solo developer working on a small app with just one target in your Xcode project, you might assume you won't encounter many challenges. However, you'd be surprised to learn that these challenges can arise sooner than expected. The term “scale” doesn't have a strict definition; its meaning varies depending on the context. At Tuist, **we think of scaling development as the process of ensuring that development remains enjoyable and productive, no matter the size of the app, project, or team involved.** By decoupling these variables, you set the foundation for healthy, motivated teams, which often leads to better ideas—and ultimately, better apps.

*Did you know that Ruby on Rails is designed to [optimize for developer happiness](https://rubyonrails.org/doctrine#optimize-for-programmer-happiness)?* Apple takes a similar approach with Xcode, especially when you're just getting started. But as your project grows, the fun and ease of development can begin to fade. So, why does this happen? To understand this shift, we need to examine a principle that Apple consistently applies in its tools, and which we believe plays a key role in why things stop being fun after a certain point: convenience through implicitness.

## Convenience through implicitness

Xcode and Xcode projects were once much simpler. Initially, there was only one platform to support: OSX. However, with the rise of open-source software and platforms like Git, the cost of producing software dropped, sparking an era of remarkable innovation. This innovation gave birth to new platforms, and as a result, Xcode and its projects had to evolve to meet the growing demands: sharing code, compiling a new programming language like Swift, supporting multiple platforms, and more. Managing such a vast ecosystem of app developers is no small feat, and Apple did an impressive job. They navigated the rapid pace of change while ensuring developers could transition smoothly.

However, in addressing some of these challenges, Apple introduced a reliance on implicit behavior and side effects as part of the system's design. While this approach worked well in practice, it also created a form of technical debt that developers continue to bear—and which still surfaces in the design of newer tools and systems. This may sound abstract, but let's break it down and make things more concrete.

## Sharing code

Sooner or later in the life of the project, you need to share code within your app, whether through frameworks or libraries you've created to use with extensions, or to enforce access boundaries and improve your app's architecture. You'll also likely rely on third-party packages from other developers. You can think of your project as a [directed acyclic graph (DAG)](https://en.wikipedia.org/wiki/Directed_acyclic_graph), where each node represents a module—often modeled by an Xcode target, like a library or framework. Now, here's the challenge: **managing this graph is hard**. Adding or removing a module can create ripple effects throughout the entire system. For example, a dynamic framework might require certain upstream targets to embed it, or transitive static symbols leaking through a dynamic module could force their Swift module interfaces to be exposed elsewhere in the graph.

If this sounds too abstract, think of it this way: *you can't just drag and drop modules in and out of the project without consequences.* With one or two modules, you might get by, but as the graph grows, so does the complexity of the relationships between modules—and with it, the risk of breaking something. Some developers we've spoken to have described this issue as “needing to learn how Xcode works.” But we don't think developers should have to. **Modularization is a standard requirement in almost every project, and it should be simple by default.**

Did you know that your project might compile successfully purely due to side effects from previous compilation steps? One of your targets might resolve an import from another target not because it's declared as a dependency, but because it was already present in derived data.

Then there are the common questions developers face: *Should this module be static or dynamic? Should it be a framework or a library? Can this product type embed dynamic frameworks? And what about dynamic libraries? What are the implications of linking a static library transitively?* These are questions we ask ourselves frequently, and often have to answer by reverse-engineering Xcode-generated projects and validating outputs with App Store Connect. Surprisingly, this crucial knowledge—rarely discussed in depth—can have serious implications for your app, from runtime crashes to unnecessarily bloating its size.

In this case, the convenience of implicitness manifests as longer build times or build errors. Implicitness, along with things like [mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries), are additional variables that introduce build-time complexity and variability, which can not only impact build performance but also make certain features, like Swift Previews, work inconsistently.

## My Swift previews stopped working

We've seen countless developers give up on Swift Previews. At some point, their Previews simply stopped working, and they couldn't pinpoint why. While the exact causes are hard to determine—largely due to Xcode being closed-source—we can still make educated guesses about where the issue might be.

Imagine you're working in the Xcode editor with a preview open, and you change a line of code, either in the preview or in the transitive code it depends on. The editor must figure out what needs to be compiled and when in order to refresh the preview. As you might imagine, the larger and more implicitly linked the project graph becomes, the more difficult this task is for Xcode, leading to inconsistencies. It's ironic that features like implicit linking and embeddable frameworks, which were designed for convenience, can also introduce frustrations. It's no surprise that Swift Previews tend to work more reliably with dynamic frameworks, which are more self-contained, compared to libraries that require additional exposure of Swift modules or headers.

Our advice to teams has always been to make implicit dependencies explicit, eliminating variables that the build system would otherwise need to resolve, such as whether an embeddable framework should be static or dynamic, or whether an import Foo statement means the target intends to depend on `Foo`. Developers are often surprised when we recommend against using certain newly announced features. After all, who would expect these innovations to impact their projects negatively?

That said, we're optimistic about the future. Xcode's build system, while it may need to take a few steps back to reassess the path forward, is in the process of laying a more solid foundation. This will support exciting, compiler-dependent features like Swift Macros, enabling them to truly shine. In a sense, **Apple is fixing the plane while flying it—because the business demands it—but we believe that a strategic “landing” to gain perspective would greatly benefit the entire ecosystem in the long run.**

If any of this still seems abstract or exaggerated, let's pause and examine a phenomenon we've been observing for quite some time.

## SPM as a project manager

Have you noticed developers turning to Swift Package Manager (SPM) as their project manager? While part of the motivation is the appeal of describing dependencies in Swift, we believe **the real excitement comes from SPM's ability to propose an alternative way of defining a graph of modules.** With SPM, you don't have to worry about whether something is static or dynamic (unless you want to) or if resources need to be bundled and copied. Like Tuist, SPM conceptually simplifies the complexity of linking, which naturally excites developers. Who wouldn't be? It's so appealing that many developers have tried replacing their Xcode projects entirely with SPM. Did Apple foresee this? Probably not. What seemed like a promising future for developers has turned into yet another challenge for Apple to tackle.

Apple now faces the task of reconciling two languages for defining module graphs: the one implicitly and "explicitly" codified in Xcode projects, and the one explicitly defined in Swift Packages. We say "explicitly" in quotes because, unsurprisingly, implicit behavior has also made its way into SPM. For example, packages that depend on `XCTest` are automatically discovered by SPM, even when they extend or wrap APIs. Additionally, Apple has to juggle two different build processes that must integrate as seamlessly as possible with Xcode. As many developers have experienced, this hasn't gone as smoothly as hoped. Package resolution can sometimes fail, leaving Xcode in a strange state, or result in invalid resolution states that are hard to recover from.

Xcode was originally designed with the assumption that all the information needed to code and build a project was contained within the Xcode project itself. But with the introduction of SPM, this assumption was upended. Now, the module graph is resolved asynchronously and communicated back to Xcode, which must adjust its UI accordingly. Reconciling these two approaches has been challenging and costly to maintain, making the system prone to regressions.

Let's not forget that when you add a dependency, SPM tries its best to make sure it works in your project, even if that means sometimes passing flags to avoid over-optimizations that could cause compilation issues. While this ensures your project builds, it can come at the cost of increased app size.

While we may not fully understand how Apple engineers manage to reconcile this internally, we recognize the complexity involved. Still, we remain optimistic: imagine if the time currently spent resolving these integration challenges could be redirected toward enhancing features. It's an exciting prospect, and we believe the groundwork being laid today will lead to a more streamlined and robust future for both Xcode and SPM.

## What if the plane could be landed?

Imagine for a moment that Apple could pause, step back, and simplify the existing complexities, rather than adding more systems and languages that need to be reconciled. What might that future look like? It's an intriguing question—one we think about a lot, and we'd like to share our thoughts with you in this blog post. Admittedly, this vision is quite idealistic, and in reality, there are many factors beyond the technical that could make it difficult to achieve. But in a world where those obstacles didn't exist, here's what we'd love to see:

### A unified graph language

This applies to both local and remote targets—we don't see a reason why there should be two separate systems. The need to reconcile them creates a problem that shouldn't exist in the first place. Ideally, the language used should be fast to evaluate and free from side effects. Is Swift the right choice for this? We're not sure. On one hand, being able to declare things in Swift is fantastic—it's one of the main reasons developers love the language. But on the other hand, side effects are inevitable, and they go against the principle of predictable behavior. Swift doesn't seem to enforce this strongly enough. Bazel developed its own language, [Startlark](https://bazel.build/rules/language), to avoid such issues—*could something similar be an option here?*

### An optimizable build system

A build system should be hermetic, with steps that are cacheable. As codebases grow larger, especially with the increasing number of supported platforms, faster hardware can only do so much. The pace at which compilation times are slowing down far outstrips hardware improvements. We've seen companies where CI turnaround times stretch to an hour—and no, it wasn't Meta. This could happen to any team if a small app becomes successful and evolves into a large, complex project.

### Implicitness as an invalid state

Implicitness should never have been accepted as a valid state in Xcode projects, and it certainly shouldn't have carried over into SPM. The build system should enforce explicit declarations—if something isn't explicitly defined, the compilation should fail immediately. Developers shouldn't have to wait minutes only to get a "framework not found" error. The system should construct the graph, analyze it, and fail right away if something is wrong. Developers' time is invaluable and shouldn't be wasted. And yes, this means rethinking how derived data stores build artifacts.

### Default to automatic static/dynamic and framework/library decision

Developers shouldn't have to worry about whether something should be static or dynamic, or whether it should be a framework or a library. With knowledge of the module graph, the destination platform, and the build configuration, the build system should be able to make these decisions deterministically, while still giving users the option to take control when necessary. Apple already knows, for example, that iOS apps can't include dynamic libraries—so why put developers in the position of having to dig up this information and make these choices themselves?

Apple has taken a step in this direction with `.automatic` linking in Swift Packages, but what about project modules? This is why we advocate for a unified language that spans both local and remote modules—it needs to be consistent across the board.

### Atomic output products

By making output products fully atomic, you enable developers to easily share artifacts that others can simply drag and drop into their projects—no fuss, and everything just works. You might be thinking, "Isn't that already the case with XCFrameworks?" It was definitely a step in the right direction, but it's not entirely atomic. For example, if a dynamic XCFramework links a Swift library statically and the symbols aren't private, you'd have to distribute the transitive Swift modules separately because you can't include more than one `.swiftmodule` in an XCFramework.

And what if someone shares a static pre-compiled binary with you that causes duplicated symbols or bloats your binary size? Ideally, Apple's system could detect this, wrap the static binary in a dynamic one, and ensure everything works smoothly.

### More documentation

We need more comprehensive documentation on the various product types (e.g., app, framework, library, extension), valid graph configurations—such as including extensions in apps—and addressing inconsistencies across platforms, which ideally should be eliminated. While this knowledge is currently codified in Xcode's “create target/project” template, it should be accessible elsewhere.

Even better, a new language could reduce the need for extensive documentation. Instead of thinking in terms of “embed this framework into this bundle,” “make this target static,” or “share this dynamic framework with the extension,” developers could simply express it as, “my app has an extension, and they both share utilities in this module.” Wouldn't that align more closely with developers' mental models?

## Closing words

**It would be fantastic if Tuist's project generation feature were unnecessary. This would signal that Xcode's fundamentals have evolved to meet the current and future needs of companies and developers.** We don't believe the solution is to replace Xcode's build system with another like Bazel. Instead, we'd love to see Apple invest in enhancing the existing system. If communicated well, the community would understand that this may come with some initial pain, but ultimately lead to a more reliable and faster app-building experience—exciting more developers and enabling them to work more efficiently.

Tuist, like [CocoaPods](https://cocoapods.org) before it, had to adopt project generation because there were no better alternatives. While we will continue to support organizations in this way, we envision a future where we can evolve into an extension of the build system, adding extra capabilities through a server and database. We're already moving in that direction, but we also need to devote significant energy to managing and simplifying the complexity that exists in Xcode projects.

We love Swift, but we also have a deep appreciation for [Elixir](https://elixir-lang.org/) and [Erlang](https://www.erlang.org/). These languages demonstrate how modeling a problem space can significantly impact the simplicity of the solutions you create. Erlang's approach with processes is a prime example, and we believe **Apple's ecosystem is ready for a language that can elevate Xcode to where it deserves to be.**

Apple and the Xcode team, you've done an incredible job. We admire Xcode and many of its features, which are ahead of many other editors. However, the current foundation limits some of that potential. **So, shall we land that plane?**
