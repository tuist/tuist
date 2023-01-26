---
title: µFeatures Architecture
slug: '/building-at-scale/microfeatures'
description: 'This document describes an approach for architecting a modular Apple OS application to enable scalability, optimize build and test cycles, and ensure good practices.'
---

import { MicroFeature, Layers } from './components/microfeatures'

uFeatures is an architectural approach to structure Apple OS applications to enable scalability, optimize build and test cycles, and ensure good practices in your team. Its core idea is to build your apps by building independent features that are interconnected using clear and concise APIs.

These guidelines introduce the principles of the architecture, helping you identify and organize your application features in different layers. It also introduces tips, tools and advice if you decide to use this architecture.

:::info Name
The name uFeatures _(microfeatures)_ comes from the [microservices architecture](https://martinfowler.com/articles/microservices.html), where different "backend features" run as different services with defined APIs to enable communication between them.
:::

### Context

Apps are made of features. Typically these features are part of the same module, or target where the whole application is defined. The natural inclination in the team is to continue building features and its tests in the same targets. As a result, the application and its tests target grows in complexity which manifests in bugs, bad compilation times, and team performance. What seemed to be a good architecture, doesn't work out that well in large codebases or teams.

This is frequently a big source of frustration when it comes to work on those projects. The time we spend goes into compiling rather than building and experimenting with the platform.

### Motivation

The µFeatures's main motivation is to support the scalability of large Xcode codebases leveraging platform features and tools. There are other solutions out there that could be also be considered to overcome those issues. A very popular one nowadays is [React Native](https://facebook.github.io/react-native/) that leverages the Javascript dynamism to offer developers a pleasant experience working in the code base, but at the same time a native experience from the user point of view.

**We believe that the usage of native tools and technologies can be optimized to overcome scalability challenges that sooner or later show up in our projects**

### Before reading

- Don't expect this to be a silver-bullet solution to your problems. You should take the core ideas, process them, and apply the principles to your projects.
- Each project is different, and so are the needs. With the ideas in the guidelines, and your needs, you should figure out what might work out for you.
- Since everything this architecture depends on is evolving _(tools, languages, concepts)_, the guidelines might get outdated very quickly. If that happens, don't hesitate to open a PR and contribute with keeping this guidelines up to date.
- It can very tempting to scale your app architecture before it actually needs it. If your app needs it, you'll notice it, and only at that point, you should consider start tackling the issue.

### Core principle

Developers should be able to **build, test and try** their features fast, with independence of the main app.

### What is a µFeature

A µFeature represents an application feature and is a combination of the following five targets _(referring with target to a Xcode target)_:

- **Source:** Contains the feature source code _(Swift, Objective-C, C++, React Native...)_ and its resources _(images, fonts, storyboards, xibs)_.
- **Interface:** It's a companion target that contains the public interface and models of the feature.
- **Tests:** Contains the feature unit and integration tests.
- **Testing:** Provides testing data that can be used for the tests and from the example app. It also provides mocks for uFeature classes and protocols that can be used by other features as we'll see later.
- **Example:** Contains an example app that developers can use to try out the feature under certain conditions _(different languages, screen sizes, settings)_.

The diagram below shows the dependencies between the targets:

- **Feature:** depends on `FeatureInterface` because it contains the models and the interfaces for which it provides implementations.
- **FeatureTesting:** depends on `FeatureInterface` because it contains test data and mocks for the models and interfaces contained in it.
- **FeatureTests:** depends on `Feature` because it contains the subjects under test and test data that can be used from the test classes.
- **FeatureExample:** depends on `FeatureTesting` to have access to the test data, and `Feature` to instantiate the implementations and showcase them from the example app.

  <MicroFeature />

### Why a µFeature

#### Clear and concise APIs

When all the app source code lives in the same target is very easy to build implicit dependencies in code, and end up with the so well-known spaghetti code. Everything is strongly coupled, the state is sometimes unpredictable, and introducing new changes become a nightmare. When we define features in independent targets we need to design public APIs as part of our feature implementation. We need to decide what should be public, how our feature should be consumed, what should remain private. We have more control over how we want our feature clients to use the feature and we can enforce good practices by designing safe APIs.

#### Small modules

[Divide and conquer](https://en.wikipedia.org/wiki/Divide_and_conquer). Working in small modules allows you to have more focus and test and try the feature in isolation. Moreover, development cycles are much faster since we have a more selective compilation, compiling only the components that are necessary to get our feature working. The compilation of the whole app is only necessary at the very end of our work, when we need to integrate the feature into the app.

#### Reusability

Reusing code across apps and other products like extensions is encouraged using frameworks or libraries. By building µFeatures reusing them is pretty straightforward. We can build an iMessage extension, a Today Extension, or a watchOS application by just combining existing µFeatures and adding _(when necessary)_ platform-specific UI layers.

### Types of µFeatures

#### Foundation

Foundation µFeatures contain foundational tools _(wrappers, extensions, ...)_ that are combined to build other µFeatures. Thus other µFeatures have access to the foundation ones. Some examples of foundations µFeatures are:

- **µUI:** Provides custom views, UIKit extensions, fonts, and colors that are used to build user-facing layouts.
- **µTesting:** Facilitates testing by providing XCTest extensions as well as custom assertions.
- **µCore:** It can be seen as the `Foundation` of your app, providing tools such as analytics reporter, logger, API client or a storage class.

In practice, foundation µFeatures expose interfaces (Structs, Classes, Enums) and extensions of platform frameworks such as `XCTest`, `Foundation` or `UIKit`.

:::note Static instances
Foundation µFeatures shouldn't expose static instances that are globally accessed. As we'll see later, it's up to the app to control the lifecycle of those foundation dependencies, and pass them to other µFeatures using dependency injection.
:::

#### Product

Product µFeatures contain features that the user can feel and interact with. They are built by combining foundation µFeatures. Some examples of product µFeatures are:

- **µSearch:** Contains your product search feature that allows users searching content on the platform.
- **µPayments:** Contains the business logic to handle payment flows and upsell screens to upgrade users to premium plans.
- **µHome:** Contains the product home screen with the most recent platform content.

:::note Product domain
Product µFeatures usually represent your product's features.
:::

In practice, product µFeatures expose **views** and **services**. In the following sections we'll see how the app target uses those views and services to build up the app.

### Dependencies between µFeatures

When a µFeature depends on another µFeature, it declares a dependency against its interface target. The benefit of this is two-fold. It prevents the implementation of a µFeature to be coupled to the implementation of another µFeature, and it speeds up clean builds because they only have to compile the implementation of our feature, and the interfaces of direct and transitive dependencies. This approach is inspired by SwiftRock's idea of [Reducing iOS Build Times by using Interface Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Note that this approach comes at the cost of a bit of overhead doing dependency injection gluing all the µFeatures together.
You can massage that cost by making an exception with the foundation µFeatures.
Product µFeatures could have a direct dependency with the implementation of foundation µFeatures.
That'd remove the need of an interface target for the core µFeatures.

### Hooking µFeatures

As we mentioned earlier, µFeatures **don't expose instances** and it's the app responsibility to create instances and use them. How we instantiate and hook µFeatures depends on the type of µFeature.

#### Services

Apps usually have services or utils whose state is tied to the application lifecycle. Those instances are global and the majority of the features will need to access them.

```swift
// Services.swift in the main application
import uCore
import uPlayback

class Services {
    static let playback = PlaybackService() // From uPlayback
    static let client = Client(baseUrl: "https://api.tuist.io") // From uCore
    static let analytics = Analytics(firebaseKey: "xxx") // From uCore
}
```

In the example above, `Services.swift` works as a static container, initializing all the services and tools with their initial state. Some of these services might need to know about the application lifecycle. We could subscribe to those notifications internally, but then we'd be coupling the service to the `NotificationCenter` and the platform-specific lifecycle notifications. What we could do instead is explicitly notifying them about the lifecycle events from the app delegate.

```swift
// AppDelegate.swift
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func applicationDidBecomeActive(_ application: UIApplication) {
        Services.playback.restoreState()
    }

}
```

#### Views/ViewControllers

On the other side, product µFeatures can also expose views and view controllers. These views usually encapsulate the logic to update themselves according to internal state changes, and react to user actions, turning those actions into state updates _(e.g. synchronizing data with the API)_.

```swift
// Home.swift in uHome
import UIKit
import uCore

public class Home {
    let client: Client
    public init(client: Client) {
        self.client = client
    }
    public func makeViewController(delegate: HomeDelegate) -> UIViewController {
        return HomeViewController(client: client, delegate: delegate)
    }
}
```

The example above shows how the home µFeature looks like. It gets initialized with its dependencies and expose a method that instantiates and returns a view controller to be used from the app. Notice that the method returns a `UIViewController` instead of a `HomeViewController`. By doing that we abstract the app from any implementation detail.

##### Delegating navigation

You might have noticed that we pass a delegate when we instantiate the view controller. The delegate responds to actions that trigger a navigation to a different µFeature. It's up to the app to define the navigation between different µFeatures. A pattern that works very well here is the [Coordinator Pattern](https://vimeo.com/144116310) that allows you represent your navigation as a tree of coordinators. These coordinators would be in the app, responding to µFeatures actions, and triggering the navigation to other coordinators.

Delegating the navigation to the app gives us the flexibility to change the navigation based on the product where we are consuming the µFeature from. Let's take an hypothetical search µFeature that exposes a search view controller. When we use that view controller from the app, we want to navigate to another µFeature when the user taps in one of the search results. However, if we use that view controller from an iMessage extension, we want the action to be different, and instead, share the search result with one of your contacts.

### Dependencies

As soon as you start building µFeatures you'll realize that most of the features need dependencies that are injected from the app. We could inject those dependencies in the constructor but we'd end up with constructors with a long list of parameters being passed. Instead, we could leverage protocols to represent the µFeatures dependencies and pass them easily _(credits to [@andreacipriani](https://github.com/andreacipriani) for coming up with this approach)_:

```swift
public protocol BaseDependencies {
    func makeClient() -> Client
    func makeLogger() -> Logger
}
```

A protocol defines the base dependencies that are the most common dependencies across all the features. Dependencies are exposed through methods that return the dependency as a return parameter of those methods.

```swift
class AppDependencies: BaseDependencies {
    func makeClient() -> Client {
        return Services.client
    }
    func makeLogger() -> Logger {
        return Services.logger
    }
}
```

From the app we conform the `BaseDependencies` protocol, defining a class, `AppDependencies` that represents our application base dependencies.

```swift
public protocol SearchDependencies: BaseDependencies {
    func makeAnalytics() -> Analytics
}
```

For some particular µFeatures, we might need some extra dependencies. We can define those in a new protocol that conforms the `BaseDependencies` protocol, adding the extra dependencies. In the example below `SearchDependencies` exposes also an `Analytics` dependency.

```swift
public final class SearchBuilder {

    private let dependenciesSolver: SearchDependencies

    public init(dependenciesSolver: SearchDependencies) {
        self.dependenciesSolver = dependenciesSolver
    }

    public func makeViewController() -> UIViewController {
        let client = dependenciesSolver.makeClient()
        let logger = dependenciesSolver.makeLogger()
        let analytics = dependenciesSolver.makeAnalytics()
        return SearchViewController(client: client, logger: logger, analytics: analytics)
    }
}

// From the app
let searchBuilder = SearchBuilder(dependenciesSolver: AppDependencies())
```

The example above shows how we can inject dependencies in a builder that builds the µFeature instance, in this case a `UIViewController`.

:::note Alternatives
This is just an example of how we can simplify dependency injection. There are other alternatives out there. It's up to you to pick up the one that works best for your project and setup.
:::

### Choosing the target product

When architecting a modular app,
a question that arises often is whether targets should be frameworks or libraries, and whether they should be static or dynamic.
In pre-Tuist era, there were many factor that influenced that decision:

- Whether the target includes resources or not.
- Whether the target depends on static targets that might lead to duplicated symbols issues upstream.
- The number of dynamic targets that need to be linked at startup time and therefore might increase the time to launch the app.

Thanks to Tuist,
the decision process has been notably simplified.
Since Tuist supports defining resources in libraries,
we recommend sticking to **static libraries**,
unless you come across scenarios where a dynamic framework is more suitable.
Bear in mind that Tuist makes changing the product a seamless process as long as you use the [standard interface](guides/resources.md) for accessing resources.

### Frequently asked questions

##### One or multiple Git repositories?

If you are working with git branches, we recommend you to keep everything in the same repository for convenience reasons. Facebook is a good example of a huge company keeping all the projects in a single repositories and Uber [wrote about it](https://eng.uber.com/ios-monorepo/) a year ago.

##### How do you version µFeatures?

If µFeatures are part of the same repository, they are versioned with the app. If you have them in different repositories you can use Git Submodules, Carthage, or your own dependency resolver to fetch specific versions of your µFeatures to link from the app.

##### How to add external dependencies?

This architecture doesn't limit you from using external dependencies. If you want to use an external dependency from a µFeature framework, we recommend you to use [Carthage](https://github.com/carthage) or the [Swift Package Manager](https://swift.org/package-manager/).

### Resources

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Leveraging frameworks to speed up our development on iOS - Part 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library Oriented Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [The Unofficial Guide to xcconfig files](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Static and Dynamic Libraries](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
