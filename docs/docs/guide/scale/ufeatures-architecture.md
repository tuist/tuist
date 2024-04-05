# µFeatures architecture


uFeatures is an architectural approach to structure Apple OS applications to enable scalability, optimize build and test cycles, and ensure good practices in your team. Its core idea is to build your apps by building independent features that are interconnected using clear and concise APIs.

These guidelines introduce the principles of the architecture, helping you identify and organize your application features in different layers. It also introduces tips, tools and advice if you decide to use this architecture.

> [!INFO] NAME
> The name uFeatures (microfeatures) comes from the [microservices architecture](https://martinfowler.com/articles/microservices.html), where different "backend features" run as different services with defined APIs to enable communication between them.


## Context

Apps are made of features. Typically these features are part of the same module, or target where the whole application is defined. The natural inclination in the team is to continue building features and its tests in the same targets. As a result, the application and its tests target grows in complexity which manifests in bugs, bad compilation times, and team performance. What seemed to be a good architecture, doesn't work out that well in large codebases or teams.

This is frequently a big source of frustration when it comes to work on those projects. The time we spend goes into compiling rather than building and experimenting with the platform.

## Motivation

The µFeatures's main motivation is to support the scalability of large Xcode codebases leveraging platform features and tools. There are other solutions out there that could be also be considered to overcome those issues. A very popular one nowadays is [React Native](https://facebook.github.io/react-native/) that leverages the Javascript dynamism to offer developers a pleasant experience working in the code base, but at the same time a native experience from the user point of view.

> [!IMPORTANT] NATIVE DEVELOPMENT CAN SCALE
> We believe that the usage of native tools and technologies can be optimized to overcome scalability challenges that sooner or later show up in our projects**

### Before reading

- Don't expect this to be a silver-bullet solution to your problems. You should take the core ideas, process them, and apply the principles to your projects.
- Each project is different, and so are the needs. With the ideas in the guidelines, and your needs, you should figure out what might work out for you.
- It can very tempting to scale your app architecture before it actually needs it. If your app needs it, you'll notice it, and only at that point, you should consider start tackling the issue.

## Core principle

Developers should be able to **build, test and try** their features fast, with independence of the main app.

## What is a µFeature

A µFeature represents an application feature and is a combination of the following five targets (referring with target to a Xcode target):

- **Source:** Contains the feature source code (Swift, Objective-C, C++, React Native...) and its resources (images, fonts, storyboards, xibs).
- **Interface:** It's a companion target that contains the public interface and models of the feature.
- **Tests:** Contains the feature unit and integration tests.
- **Testing:** Provides testing data that can be used for the tests and from the example app. It also provides mocks for uFeature classes and protocols that can be used by other features as we'll see later.
- **Example:** Contains an example app that developers can use to try out the feature under certain conditions (different languages, screen sizes, settings).

We recommend following a naming convention for targets, something that you can enforce in your project thanks to Tuist's DSL.

| Target | Dependencies | Content |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | Source code and resources |
| `FeatureInterface` | - | Public interface and models |
| `FeatureTests` | `Feature`, `FeatureTesting` | Unit and integration tests |
| `FeatureTesting` | `Feature` | Testing data and mocks |
| `FeatureExample` | `FeatureTesting`, `Feature` | Example app |

> [!IMPORTANT] COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
> Alternatively, you can use compiler directives to include test data and mocks in the mani feature target when compiling for `Debug`. You simplify the graph, but you'll end up compiling code that you won't need for running the app.

## Why a µFeature

### Clear and concise APIs

When all the app source code lives in the same target is very easy to build implicit dependencies in code, and end up with the so well-known spaghetti code. Everything is strongly coupled, the state is sometimes unpredictable, and introducing new changes become a nightmare. When we define features in independent targets we need to design public APIs as part of our feature implementation. We need to decide what should be public, how our feature should be consumed, what should remain private. We have more control over how we want our feature clients to use the feature and we can enforce good practices by designing safe APIs.

### Small modules

[Divide and conquer](https://en.wikipedia.org/wiki/Divide_and_conquer). Working in small modules allows you to have more focus and test and try the feature in isolation. Moreover, development cycles are much faster since we have a more selective compilation, compiling only the components that are necessary to get our feature working. The compilation of the whole app is only necessary at the very end of our work, when we need to integrate the feature into the app.

### Reusability

Reusing code across apps and other products like extensions is encouraged using frameworks or libraries. By building µFeatures reusing them is pretty straightforward. We can build an iMessage extension, a Today Extension, or a watchOS application by just combining existing µFeatures and adding _(when necessary)_ platform-specific UI layers.

## Types of µFeatures

### Foundation

Foundation µFeatures contain foundational tools (wrappers, extensions, ...) that are combined to build other µFeatures. Thus other µFeatures have access to the foundation ones. Some examples of foundations µFeatures are:

- **µUI:** Provides custom views, UIKit extensions, fonts, and colors that are used to build user-facing layouts.
- **µTesting:** Facilitates testing by providing XCTest extensions as well as custom assertions.
- **µNetwork:** It contains utilities and tools to interact with the network.

In practice, foundation µFeatures expose interfaces (Structs, Classes, Enums) and extensions of platform frameworks such as `XCTest`, `Foundation` or `UIKit`.

> [!WARNING] STATIC INSTANCES
> Foundation µFeatures shouldn't expose static instances that are globally accessed. As we'll see later, it's up to the app to control the lifecycle of those foundation dependencies, and pass them to other µFeatures using dependency injection.

> [!TIP] MODULE SIZE AND INCREMENTAL BUILDS AND BINARY CACHING EFFECTIVENESS
> We recommend smaller and more focused foundation µFeatures to achieve the highest performance of incremental builds and [Tuist Cloud binary caching](/cloud/binary-caching)

<!-- > If you use [Tuist Cloud binary caching]() -->

### Product

Product µFeatures contain features that the user can feel and interact with. They are built by combining foundation µFeatures. Some examples of product µFeatures are:

- **µSearch:** Contains your product search feature that allows users searching content on the platform.
- **µPayments:** Contains the business logic to handle payment flows and upsell screens to upgrade users to premium plans.
- **µHome:** Contains the product home screen with the most recent platform content.

> [!NOTE] PRODUCT DOMAIN
> Product µFeatures usually represent your product's features.

In practice, product µFeatures expose **views** and **services**. In the following sections we'll see how the app target uses those views and services to build up the app.

## Dependencies

When a µFeature depends on another µFeature, it declares a dependency against its interface target. The benefit of this is two-fold. It prevents the implementation of a µFeature to be coupled to the implementation of another µFeature, and it speeds up clean builds because they only have to compile the implementation of our feature, and the interfaces of direct and transitive dependencies. This approach is inspired by SwiftRock's idea of [Reducing iOS Build Times by using Interface Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

> [!WARNING] WORK IN PROGRESS
> We are currently exploring how to dependency injection in Tuist's codebase and we'll update this section with the best practices and recommendations.

## Choosing the target product

When architecting a modular app,
a question that arises often is **whether targets should be frameworks or libraries**, and whether they should be static or dynamic.
In pre-Tuist era, there were many factor that influenced that decision:

- Whether the target includes resources or not.
- Whether the target depends on static targets that might lead to duplicated symbols issues upstream.
- The number of dynamic targets that need to be linked at startup time and therefore might increase the time to launch the app.

Thanks to Tuist,
the decision process has been notably simplified.
Since Tuist supports defining resources in libraries,
we recommend sticking to **static libraries**,
unless you come across scenarios where a dynamic framework is more suitable.

Bear in mind that Tuist makes changing the product a seamless process as long as you use the standard interface.

## Frequently asked questions

### One or multiple Git repositories?

If you are working with git branches, we recommend you to keep everything in the same repository for convenience reasons. Facebook is a good example of a huge company keeping all the projects in a single repositories and Uber [wrote about it](https://eng.uber.com/ios-monorepo/) a year ago.

### How do you version µFeatures?

If µFeatures are part of the same repository, they are versioned with the app. If you have them in different repositories you can use Git Submodules, Carthage, or your own dependency resolver to fetch specific versions of your µFeatures to link from the app.

### How to add external dependencies?

This architecture doesn't limit you from using external dependencies. If you want to use an external dependency from a µFeature framework, we recommend you to use the [Swift Package Manager](https://swift.org/package-manager/).

## Resources

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Leveraging frameworks to speed up our development on iOS - Part 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library Oriented Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [The Unofficial Guide to xcconfig files](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Static and Dynamic Libraries](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
