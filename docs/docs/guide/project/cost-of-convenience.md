---
title: The cost of convenience
description: Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it.
---

# The cost of convenience

Designing a code editor that the spectrum **from small to large-scale projects can use** is a challenging task. 
Many tools approach the problem by layering their solution and providing extensibility. The bottom-most layer is very low-level and close to the underlying build system, and the top-most layer is a high-level abstraction that's convenient to use but less flexible.
By doing so, they make the simple things easy, and everything else possible.

However,
**[Apple](https://www.apple.com) decided to take a different approach with Xcode**.
The reason is unknown, but it's likely that optimizing for the challenges of large-scale projects has never been their goal.
They overinvested in convenience for small projects,
provided little flexibility,
and strongly coupled the tools with the underlying build system.
To achieve the convenience, they provide sensible defaults, which you can easily replace,
and added a lot of implicit build-time-resolved behaviors that are the culprit of many issues at scale.

## Explicitness and scale

When working at scale, **explicitness is key**.
It allows the build system to analyze and understand the project structure and dependencies ahead of time,
and perform optimizations that would be impossible otherwise.
The same explicitness is also key in ensuring that editor features such as [SwiftUI previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) or [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) work reliably and predictably.
Because Xcode and Xcode projects embraced implicitness as a valid design choice to achieve convenience,
a principle that the Swift Package Manager has inherited,
the difficulties of using Xcode are also present in the Swift Package Manager.

> [!INFO] THE ROLE OF TUIST
> We could summarize Tuist's role as a tool that prevents implicitly-defined projects and leverages explicitness to provide a better developer experience (e.g. validations, optimizations). Tools like [Bazel](https://bazel.build) take it further by bringing it down to the build system level.

This is an issue that's barely discussed in the community, but it's a significant one.
While working on Tuist,
we've noticed many organizations and developers thinking that the current challenges they face will be addressed by the [Swift Package Manager](https://www.swift.org/documentation/package-manager/),
but what they don't realize is that because it's building on the same principles,
even though it mitigates the so well-known Git conflicts,
they degrade the developer experience in other areas and continue to make the projects non-optimizable.

In the following sections, we'll discuss some real examples of how implicitness affects the developer experience and the project's health. The list is not exhaustive, but it should give you a good idea of the challenges that you might face when working with Xcode projects or Swift Packages.

## Convenience getting in your way

### Shared built products directory

Xcode uses a directory inside the derived data directory for each product.
Inside it, it stores the build artifacts, such as the compiled binaries, the dSYM files, and the logs.
Because all the products of a project go into the same directory,
which is visible by default from other targets to link against,
**you might end up with targets that implicitly depend on each other.**
While this might not be a problem when having just a few targets,
it might manifest as failing builds that are hard to debug when the project grows. 

The consequence of this design decision is that many projects acidentally compile with a graph that is not well-defined.

> [!TIP] TUIST ENFORCEMENT OF EXPLICIT DEPENDENCIES
> Tuist provides a generation configuration option to disallow implicit dependencies. When enabled, if a target tries to import a dependencies that's not explicitly declared, the build will fail.

### Find implicit dependencies in schemes

Defining and maintaining a dependency graph in Xcode gets harder as the project grows.
It's hard because they are codified in the `.pbxproj` files as build phases and build settings,
there are no tools to visualize and work with the graph,
and the changes in the graph (e.g. adding a new dynamic precompiled framework),
might require configuration changes upstream (e.g. adding a new build phase to copy the framework into the bundle).

Apple decided at some point that instead of evolving the graph model into something more manageable,
it'd make more sense to add an option to resolve implicit dependencies at build time.
This is once again a questionable design choice because you might end up with slower build times or unpredictable builds.
For example, a build might pass locally due to some state in derive data,
which acts as a [singleton](https://en.wikipedia.org/wiki/Singleton_pattern),
but then fail to compile on CI because the state is different.

> [!TIP]
> We recommend disabling this in your project schemes, and use like Tuist that eases the management of the dependency graph.

### SwiftUI Previews and static libraries/frameworks

Some editor features like SwiftUI Previews or Swift Macros require the compilation of the dependency graph from the file that's being edited. This integration between the editor requires that the build system resolves any implicitness and output the right artifacts that are necessary for those features to work. As you can imagine, **the more implicit the graph is, the more challenging the task is for the build system**, and therefore it's not surprising that many of these features don't work reliably. We often hear from developers that they stopped using SwiftUI previews long time ago because they were too unreliable. Instead, they are using either example apps, or avoiding certaing things, like the usage of static libraries or script build phases, because they cause the feature to break.

### Mergeable libraries

Dynamic frameworks, while more flexible and easier to work with, have a negative impact in the launch time of apps. On the other side, static libraries are faster to launch, but impact the compilation time and are a bit harder to work with, specially in complex graph scenarios. *Wouldn't it be great if you could change between one or the other depending on the configuration?* That's what Apple must have thought when they decided to work on mergeable libraries. But once again, they moved more build-time inference to the build-time. If reasoning about a dependency graph, imagine having to do so when the static or dynamic nature of the target will be resolved at build-time based on some build settings in some targets. Good luck making that work reliably while ensuring features like SwiftUI previews don't break.

**Many users come to Tuist wanting to use mergeable libraries and our answer is always the same. You don't need to.** You can control the static or dynamic nature of your targets at generation-time leading to a project whose graph is known ahead of compilation. No variables need to be resolved at build-time.

```bash
# The value of TUIST_DYNAMIC can be read from the project
# to set the product as static or dynamic based on the value.
TUIST_DYNAMIC=1 tuist generate
```

## Explicit, explicit, and explicit

If there's an important non-written principle that we recommend every developer or organization that wants their development with Xcode to scale, is that they should embrace explicitness. And if explicitness is hard to manage with raw Xcode projects, they should consider something else, either [Tuist](https://tuist.io) or [Bazel](https://bazel.build). **Only then reliability, predicability, and optimizations will be possible.**

## Future

Whether Apple will do something to prevent all the above issues is unknown.
Their continuous decisions embedded into Xcode and the Swift Package Manager don't suggest that they will.
Once you allow implicit configuration as a valid state,
**it's hard to move from there without introducing breaking changes.**
Going back to first principles and rethinking the design of the tools might lead to breaking many Xcode projects that accidentally compiled for years. Imagine the community uproar if that happened.

Apple finds itself in a bit of a chicken-and-egg problem.
Convenience is what helps developers get started quickly and build more apps for their ecosystem.
But their decisions to make the experience convenience at that scale, 
is making it hard for them to ensure some of the Xcode features work reliably.

Because the future is unknown,
we try to **be as close as possible to the industry standards and Xcode projects**.
We prevent the above issues,
and leverage the knowledge that we have to provide a better developer experience.
Ideally we wouldn't have to resort to project generation for that,
but the lack of extensibility of Xcode and the Swift Package Manager make it the only viable option.
And it's also a safe option because they'll have to break the Xcode projects to break Tuist projects.

Ideally, **the build system was more extensible**,
but wouldn't it be a bad idea to have plugins/extensions that contract with a world of implicitness?
It doesn't seem like a good idea.
So it seems like we'll need external tools like Tuist or [Bazel](https://bazel.build) to provide a better developer experience.
Or maybe Apple will surprise us all and make Xcode more extensible and explicit...

Until that happens, you have to choose whether you want to embrace the convencience of Xcode and take on the debt that comes with it, or trust us on this journey to provide a better developer experience.
We won't disappoint you.