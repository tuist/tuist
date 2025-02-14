---
title: Registry
titleTemplate: :title · Develop · Guides · Tuist
description: Tuist Registry를 사용하여 Swift 패키지 해석시간을 최적화 합니다.
---

# Registry {#registry}

> [!IMPORTANT] 요구사항
>
> - A <LocalizedLink href="/server/introduction/accounts-and-projects">Tuist account and project</LocalizedLink>

의존성이 증가함에 따라 이것을 해결하는 시간도 늘어납니다. 다른 패키지 관리 툴인 [CocoaPods](https://cocoapods.org/) 또는 [npm](https://www.npmjs.com/)는 중앙 집중식이지만 Swift Package Manager는 그렇지 않습니다. Because of that, SwiftPM needs to resolve dependencies by doing a deep clone of each repository, which can be time-consuming. To address this, Tuist provides an implementation of the [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md), so you can download only the commit you _actually need_. 레지스트리에 있는 패키지는 [Swift Package Index](https://swiftpackageindex.com/)를 기반으로 합니다 – 해당 페이지에서 패키지를 찾을 수 있다면 Tuist Registry에서도 사용할 수 있습니다. 또한 패키지는 엣지 스토리지를 통해 전세계에 분산되어 제공되며, 패키지를 확인할 때 최소한의 지연 시간으로 이용할 수 있습니다.

## Usage {#usage}

To set up and login to the registry, `cd` into your project's directory and run:

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

If you want to ensure that the registry is used every time you resolve dependencies, you will need to update `dependencies` in your `Package.swift` file to use the registry identifier instead of a URL. The registry identifier is always in the form of `{organization}.{repository}`. For example, to use the registry for the `swift-composable-architecture` package, do the following:

> [!NOTE]
> The identifier can't contain more than one dot. If the repository name contains a dot, it's replaced with an underscore.
> For example, the `https://github.com/groue/GRDB.swift` package would have the registry identifier `groue.GRDB_swift`.
