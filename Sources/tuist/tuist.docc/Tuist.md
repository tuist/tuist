# ``tuist``

Tuist is a command-line interface (CLI) designed to tackle the complexities of building large-scale applications for Apple platforms.

## Overview

As Xcode projects expand, **organizations may face a decline in productivity** due to several factors, including unreliable incremental builds, frequent clearing of Xcode's global cache by developers encountering issues, and fragile project configurations. To maintain rapid feature development, organizations typically explore various strategies.

Some organizations choose to bypass the compiler by abstracting the platform using JavaScript-based dynamic runtimes, such as [React Native](https://reactnative.dev/). While this approach may be effective, it [complicates access to the platform's native features](https://shopify.engineering/building-app-clip-react-native). Other organizations opt for **modularizing the codebase**, which helps establish clear boundaries, making the codebase easier to work with and improving the reliability of build times. However, the Xcode project format is not designed for modularity and results in implicit configurations that few understand and frequent conflicts. This leads to a bad bus factor, and although incremental builds may improve, developers might still frequently clear Xcode's build cache (i.e., derived data) when builds fail. To address this, some organizations choose to **abandon Xcode's build system** and adopt alternatives like [Buck](https://buck.build/) or [Bazel](https://bazel.build/). However, this comes with a [high complexity and maintenance burden](https://bazel.build/migrate/xcode) (e.g., Xcode updates might disrupt the integration with Bazel, which is ultimately a hack).

### Tuist

[Tuist](https://tuist.io) is a viable alternative that aids in surmounting these challenges while maintaining complexity and costs at an acceptable level. It considers Xcode projects as a fundamental element, ensuring resilience against future Xcode updates, and utilizes Xcode project generation to offer teams a modularization-focused declarative API. Tuist uses the project declaration to **simplify the complexities of modularization**, **optimize workflows** like build or test across various environments, and facilitate and **democratize the evolution of Xcode projects**.

> Warning: This website represents a partial revamp of the [Tuist documentation website](https://docs.tuist.io). For any documentation not available here, we recommend visiting the old website.

## Topics

### Articles

- <doc:Tuist-Cloud---Intro>

### Tutorials

- <doc:Tuist>
- <doc:Tuist-Cloud>

