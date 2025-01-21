---
title: Registry
titleTemplate: :title · Develop · Guides · Tuist
description: Optimize your Swift package resolution times by leveraging the Tuist Registry.
---

# Registry {#registry}

> [!IMPORTANT] REQUIREMENTS
> - A <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist account and project</LocalizedLink>

As the number of dependencies grows, so does the time to resolve them. While other package managers like [CocoaPods](https://cocoapods.org/) or [npm](https://www.npmjs.com/) are centralized, Swift Package Manager is not. Because of that, SwiftPM needs to resolve dependencies by doing a deep clone of each repository, which can be time-consuming and takes up more memory than a centralized approach would. To address this, Tuist provides an implementation of the [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), so you can download only the commits you _actually need_. The packages in the registry are based on the [Swift Package Index](https://swiftpackageindex.com/) – if you can find a package there, the package is also available in the Tuist Registry. Additionally, the packages are distributed across the globe using an edge storage for minimum latency when resolving them.

## Usage {#usage}

To set up and log in to the registry, run the following commands in your project's directory:

```bash
tuist registry setup # Creates a `registries.json` file with the default registry configuration.
tuist registry login # Logs you into the registry.
```

Now you can access the registry! To resolve dependencies from the registry instead of from source control, continue reading based on your project setup:
- <LocalizedLink href="/guides/develop/registry/xcode-project">Xcode project</LocalizedLink>
- <LocalizedLink href="/guides/develop/registry/generated-project">Generated project with the Xcode package integration</LocalizedLink>
- <LocalizedLink href="/guides/develop/registry/xcodeproj-integration">Generated project with the XcodeProj-based package integration</LocalizedLink>
- <LocalizedLink href="/guides/develop/registry/swift-package">Swift package</LocalizedLink>

To set up the registry on the CI, follow this guide: <LocalizedLink href="/guides/develop/registry/ci">Continuous integration</LocalizedLink>.

### Package registry identifiers {#package-registry-identifiers}

When you use package registry identifiers in a `Package.swift` or `Project.swift` file, you need to convert the URL of the package to the registry convention. The registry identifier is always in the form of `{organization}.{repository}`. For example, to use the registry for the `https://github.com/pointfreeco/swift-composable-architecture` package, the package registry identifier would be `pointfreeco.swift-composable-architecture`.

> [!NOTE]
> The identifier can't contain more than one dot. If the repository name contains a dot, it's replaced with an underscore.
> For example, the `https://github.com/groue/GRDB.swift` package would have the registry identifier `groue.GRDB_swift`.
