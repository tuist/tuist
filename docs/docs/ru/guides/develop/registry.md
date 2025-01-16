---
title: Registry
titleTemplate: :title · Develop · Guides · Tuist
description: Optimize your Swift package resolution times by leveraging the Tuist Registry.
---

# Registry {#registry}

> [!WARNING] BETA
> This feature is currently in beta. If you encounter any issues, please report them at our <a href="https://community.tuist.dev/c/troubleshooting-how-to/6" target="_blank">community forum</a>.

> [!IMPORTANT] REMOTE PROJECT REQUIRED
> This feature requires a <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink>.

As the number of dependencies grows, so does the time to resolve them. While other package managers like [CocoaPods](https://cocoapods.org/) or [npm](https://www.npmjs.com/) are centralized, Swift Package Manager is not. Because of that, SwiftPM needs to resolve dependencies by doing a deep clone of each repository, which can be time-consuming. To address this, Tuist provides an implementation of the [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), so you can download only the commit you _actually need_. The packages in the registry are based on the [Swift Package Index](https://swiftpackageindex.com/) – if you can find a package there, the package is also available in the Tuist Registry. Additionally, the packages are distributed across the globe using an edge storage for minimum latency when resolving them.

## Usage {#usage}

To set up and login to the registry, `cd` into your project's directory and run:

```bash
tuist registry setup # Creates a `registries.json` file with the default registry configuration.
tuist registry login # Logs you into the registry.
```

Now you can access the registry! To resolve dependencies from the registry instead of from source control, follow the section below based on your setup.

### Xcode projects {#xcode-projects}

> [!IMPORTANT] Support for Xcode projects is coming soon.
> Follow the latest development at [our community forum](https://community.tuist.dev/t/tuist-registry-initiative/262/2).

### Tuist project with the Xcode default integration {#tuist-project-with-xcode-default-integration}

> [!IMPORTANT] Support for Tuist projects with the Xcode default integration of packages is coming soon.
> Follow the latest development at [our community forum](https://community.tuist.dev/t/tuist-registry-initiative/262/2).

### Tuist project with the XcodeProj-based integration {#tuist-project-with-xcodeproj-based-integration}

If you are using the <LocalizedLink href="/guides/develop/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj-based integration</LocalizedLink>, you can use the `--replace-scm-with-registry` flag to resolve dependencies from the registry if they are available. Add it to the `installOptions` in your `Tuist.swift` file:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

If you want to ensure that the registry is used every time you resolve dependencies, you will need to update `dependencies` in your `Tuist/Package.swift` file to use the registry identifier instead of a URL. The registry identifier is always in the form of `{organization}.{repository}`. For example, to use the registry for the `swift-composable-architecture` package, do the following:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```

### Swift package {#swift-package}

If you are working on a Swift package, you can use the `--replace-scm-with-registry` flag to resolve dependencies from the registry if they are available:

```bash
swift package --replace-scm-with-registry resolve
```

If you want to ensure that the registry is used every time you resolve dependencies, you will need to update `dependencies` in your `Package.swift` file to use the registry identifier instead of a URL. The registry identifier is always in the form of `{organization}.{repository}`. For example, to use the registry for the `swift-composable-architecture` package, do the following:

```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```

## Непрерывная интеграция (CI) {#continuous-integration-ci}

To use the registry on your CI, you need to ensure that you have logged in to the registry by running `tuist registry login` as part of your workflow.

Since the registry credentials are stored in a keychain, you need to set it up as well. Note some CI providers or automation tools like [Fastlane](https://fastlane.tools/) already create a temporary keychain or provide a built-in way how to create one. However, you can also create one by creating a custom step with the following code:

```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

An example workflow for GitHub Actions could then look like this:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - run: tuist registry login
      - run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - run: tuist build
```
