---
title: Registry
titleTemplate: :title · Develop · Guides · Tuist
description: Tuist Registry를 사용하여 Swift 패키지 해석시간을 최적화 합니다.
---

# Registry {#registry}

> [!WARNING] BETA\
> 이 기능은 현재 베타 기능입니다. 문제가 발생하면 <a href="https://community.tuist.dev/c/troubleshooting-how-to/6" target="_blank">커뮤니티 포럼</a>에 남겨주시기 바랍니다.

> [!IMPORTANT] REMOTE PROJECT 필요
> 이 기능은 <LocalizedLink href="/server/introduction/accounts-and-projects">remote project</LocalizedLink>가 필요합니다.

의존성이 증가함에 따라 이것을 해결하는 시간도 늘어납니다. 다른 패키지 관리 툴인 [CocoaPods](https://cocoapods.org/) 또는 [npm](https://www.npmjs.com/)는 중앙 집중식이지만 Swift Package Manager는 그렇지 않습니다. 이로 인해 SwiftPM은 각 리포지토리의 전체를 복제하여 의존성을 해결하므로 시간이 많이 걸릴 수 있습니다. 이 문제를 해결하기 위해 Tuist는 [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) 구현을 제공하여 _실제로 필요한_ 커밋만 다운로드할 수 있습니다. 레지스트리에 있는 패키지는 [Swift Package Index](https://swiftpackageindex.com/)를 기반으로 합니다 – 해당 페이지에서 패키지를 찾을 수 있다면 Tuist Registry에서도 사용할 수 있습니다. 또한 패키지는 엣지 스토리지를 통해 전세계에 분산되어 제공되며, 패키지를 확인할 때 최소한의 지연 시간으로 이용할 수 있습니다.

## 사용법 {#usage}

레지스트리를 설정하고 로그인하려면, `cd` 명령어를 사용해 프로젝트의 디렉토리로 이동하여 다음을 수행합니다:

```bash
tuist registry setup # Creates a `registries.json` file with the default registry configuration.
tuist registry login # Logs you into the registry.
```

이제 레지스트리에 접근할 수 있습니다! 소스 컨트롤을 대신하여 레지스트리에서 의존성을 해결하려면, 사용 중인 설정에 따라 다음 섹션을 따라야 합니다.

### Xcode 프로젝트 {#xcode-projects}

레지스트리를 사용하여 패키지를 추가하려면 기본 Xcode UI를 사용합니다. Xcode의 `Package Dependencies` 탭에서 `+` 버튼을 눌러서 레지스트리에 패키지를 검색할 수 있습니다. 패키지가 레지스트리에 사용가능하면 우측 상단에 `tuist.dev` 레지스트리가 표시됩니다:

![패키지 의존성 추가](/images/guides/develop/build/registry/registry-add-package.png)

Xcode는 현재 소스 제어 패키지를 레지스트리로 자동으로 대체하는 기능을 지원하지 않습니다. 처리 속도를 높이려면 소스 제어 패키지를 삭제하고 레지스트리 패키지를 추가해야 합니다.

### Xcode 기본 통합을 사용하는 Tuist 프로젝트 {#tuist-project-with-xcode-default-integration}

If you are using the <LocalizedLink href="/guides/develop/projects/dependencies#xcodes-default-integration">Xcode's default integration</LocalizedLink> of packages with Tuist Projects, you need to use the registry identifier instead of a URL when adding a package:

```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
    ],
    .target(
        name: "App",
        product: .app,
        bundleId: "io.tuist.App",
        dependencies: [
            .package(product: "ComposableArchitecture"),
        ]
    )
)
```

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

## Continuous Integration (CI) {#continuous-integration-ci}

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
