# The Modular Architecture (TMA)


TMA is an architectural approach to structure Apple OS applications to enable scalability, optimize build and test cycles, and ensure good practices in your team. Its core idea is to build your apps by building independent features that are interconnected using clear and concise APIs.

These guidelines introduce the principles of the architecture, helping you identify and organize your application features in different layers. It also introduces tips, tools, and advice if you decide to use this architecture.

> [!INFO] µFEATURES
> This architecture was previously known as µFeatures. We've renamed it to The Modular Architecture (TMA) to better reflect its purpose and the principles behind it.

## Core principle

Developers should be able to **build, test, and try** their features fast, independently of the main app, and while ensuring Xcode features like UI previews, code completion, and debugging work reliably.

## What is a module

A module represents an application feature and is a combination of the following five targets (where target referts to an Xcode target):

- **Source:** Contains the feature source code (Swift, Objective-C, C++, JavaScript...) and its resources (images, fonts, storyboards, xibs).
- **Interface:** It's a companion target that contains the public interface and models of the feature.
- **Tests:** Contains the feature unit and integration tests.
- **Testing:** Provides testing data that can be used in tests and the example app. It also provides mocks for module classes and protocols that can be used by other features as we'll see later.
- **Example:** Contains an example app that developers can use to try out the feature under certain conditions (different languages, screen sizes, settings).

We recommend following a naming convention for targets, something that you can enforce in your project thanks to Tuist's DSL.

| Target | Dependencies | Content |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | Source code and resources |
| `FeatureInterface` | - | Public interface and models |
| `FeatureTests` | `Feature`, `FeatureTesting` | Unit and integration tests |
| `FeatureTesting` | `FeatureInterface` | Testing data and mocks |
| `FeatureExample` | `FeatureTesting`, `Feature` | Example app |

> [!TIP] UI Previews
> `Feature` can use `FeatureTesting` as a Development Asset to allow for UI previews

> [!IMPORTANT] COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
> Alternatively, you can use compiler directives to include test data and mocks in the `Feature` or `FeatureInterface` targets when compiling for `Debug`. You simplify the graph, but you'll end up compiling code that you won't need for running the app.

## Why a module

### Clear and concise APIs

When all the app source code lives in the same target it is very easy to build implicit dependencies in code and end up with the so well-known spaghetti code. Everything is strongly coupled, the state is sometimes unpredictable, and introducing new changes become a nightmare. When we define features in independent targets we need to design public APIs as part of our feature implementation. We need to decide what should be public, how our feature should be consumed, what should remain private. We have more control over how we want our feature clients to use the feature and we can enforce good practices by designing safe APIs.

### Small modules

[Divide and conquer](https://en.wikipedia.org/wiki/Divide_and_conquer). Working in small modules allows you to have more focus and test and try the feature in isolation. Moreover, development cycles are much faster since we have a more selective compilation, compiling only the components that are necessary to get our feature working. The compilation of the whole app is only necessary at the very end of our work, when we need to integrate the feature into the app.

### Reusability

Reusing code across apps and other products like extensions is encouraged using frameworks or libraries. By building modules reusing them is pretty straightforward. We can build an iMessage extension, a Today Extension, or a watchOS application by just combining existing modules and adding _(when necessary)_ platform-specific UI layers.

## Dependencies

When a module depends on another module, it declares a dependency against its interface target. The benefit of this is two-fold. It prevents the implementation of a module to be coupled to the implementation of another module, and it speeds up clean builds because they only have to compile the implementation of our feature, and the interfaces of direct and transitive dependencies. This approach is inspired by SwiftRock's idea of [Reducing iOS Build Times by using Interface Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Depending on interfaces requires apps to build the graph of implementations at runtime, and dependency-inject it into the modules that need it. Although TMA is non-opinionated about how to do this, we recommend using dependency-injection solutions or patterns or solutions that don't add built-time indirections or use platform APIs that were not designed for this purpose.

## Product types

When building a module, you can choose between **libraries and frameworks**, and **static and dynamic linking** for the targets. Without Tuist, making this decision is a bit more complex because you need to configure the dependency graph manually. However, thanks to Tuist Projects, this is no longer a problem. 

We recommend using dynamic libraries or frameworks during development using [bundle accessors](/guides/develop/projects/synthesized-files#bundle-accessors) to decouple the bundle-accessing logic from the library or framework nature of the target. This is key for fast compilation times and to ensure [SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) work reliably. And static libraries or frameworks for the release builds to ensure the app boots fast. You can leverage [dynamic configuration](/guides/develop/projects/dynamic-configuration#configuration-through-environment-variables) to change the product type at generation-time:

```bash
# You'll have to read the value of the variable from the manifest
# and use it to change the linking type
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


> [!IMPORTANT] MERGEABLE LIBRARIES
> Apple attempted to alleviate the cumbersomeness of switching between static and dynamic libraries by introducing [mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). However, that introduces build-time non-determinism that makes your build non-reproducible and harder to optimize so we don't recommend using it.

## Code

TMA is non-opinionated about the code architecture and patterns for your modules. However, we'd like to share some tips based on our experience:

- **Leveraging the compiler is great.** Over-leveraging the compiler might end up being non-productive and cause some Xcode features like previews to work unreliably. We recommend using the compiler to enforce good practices and catch errors early, but not to the point that it makes the code harder to read and maintain.
- **Use Swift Macros sparingly.** They can be very powerful but can also make the code harder to read and maintain.
- **Embrace the platform and the language, don't abstract them.** Trying to come up with ellaborated abstraction layers might end up being counterproductive. The platform and the language are powerful enough to build great apps without the need for additional abstraction layers. Use good programming and design patterns as a reference to build your features.


## Resources

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Leveraging frameworks to speed up our development on iOS - Part 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library Oriented Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [The Unofficial Guide to xcconfig files](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Static and Dynamic Libraries](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
