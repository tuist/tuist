---
title: Dependencies
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Tuist 프로젝트에서 의존성을 선언하는 방법을 알아보세요.
---

# 의존성 {#dependencies}

프로젝트 규모가 커지면 코드를 공유하고, 경계를 명확히 하며, 빌드 시간을 개선하기 위해 여러 타겟으로 나누는 것이 일반적입니다.
여러 target으로 나누게 되면 이들 사이의 의존 관계를 정의하여 **의존성 그래프**가 만들어지며, 여기에는 외부 의존성도 포함될 수 있습니다.

## XcodeProj-codified graphs {#xcodeprojcodified-graphs}

Xcode와 XcodeProj의 설계 특성상 의존성 그래프를 관리하는 일은 번거롭고 실수하기 쉬운 작업이 될 수 있습니다.
발생할 수 있는 문제들을 예로 들어보면 다음과 같습니다:

- Xcode의 빌드 시스템은 프로젝트의 모든 산출물을 derived data 내 동일한 디렉터리에 저장하기 때문에, 이로 인해 각 타겟이 원래 사용해서는 안 되는 다른 target의 산출물을 import할 수 있습니다. 클린 빌드가 더 흔하게 사용되는 CI 환경이나, 나중에 다른 구성을 사용할 때 컴파일이 실패할 수 있습니다.
- 타겟의 전이적 동적 의존성들(transitive dynamic dependencies)은 `LD_RUNPATH_SEARCH_PATHS` 빌드 설정에 포함된 모든 디렉터리에 복사되어야 합니다. 이렇게 해당 의존성들이 복사되지 않으면, 타겟이 런타임에 의존성을 찾을 수 없습니다. 의존성 그래프가 간단할 때는 생각하고 설정하기 쉽지만, 그래프가 복잡해질수록 문제가 됩니다.
- target이 정적 [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)를 링크할 때, Xcode가 번들을 처리하고 현재 플랫폼과 아키텍처에 맞는 바이너리를 추출할 수 있도록 추가 빌드 페이즈(Build Phase)가 필요합니다. 이 build phase는 자동으로 추가되지 않으며, 추가하는 것을 쉽게 잊어버릴 수 있습니다.

위의 내용들은 몇 가지 예시에 불과하며, 우리는 수년간 이보다 더 많은 문제들을 겪어왔습니다.
의존성 그래프를 관리하고 유효성을 검증하기 위해 엔지니어 팀이 필요하다고 상상해보세요.
더 안 좋은 경우는, 제어하거나 커스터마이즈할 수 없는 빌드 시스템(closed-source build system)이 빌드 시점에 이러한 복잡한 세부 사항을 해결하는 경우입니다.
어디서 많이 들어본 것 같지 않나요? 이 방식은 Apple이 Xcode와 XcodeProj에서 채택한 접근 방식이며, Swift Package Manager도 그대로 채택하고 있습니다.

의존성 그래프는 반드시 **명시적**이고 **정적**이어야 합니다. 그래야 **검증**되고 **최적화**될 수 있기 때문이죠.
Tuist와 함께라면, 의존 관계를 정의하는데만 집중하세요. 나머지는 저희가 알아서 처리할게요.
복잡한 세부 구현 사항들은 추상화되어 신경 쓸 필요가 없습니다.

다음 섹션에서는 프로젝트에서 의존성을 선언하는 방법을 알아보겠습니다.

> [!TIP] 그래프 검증
> Tuist는 프로젝트를 생성할 때 그래프를 검증하여 순환이 없고 모든 의존성이 유효한지 확인합니다. 덕분에 어떤 팀이든 그래프가 깨질 걱정 없이 의존성 그래프를 발전시킬 수 있습니다.

## 로컬 의존성 {#local-dependencies}

Target은 같은 프로젝트나 다른 프로젝트의 타겟, 그리고 바이너리에 의존할 수 있습니다.
`Target`을 생성할 때, `dependencies ` 아규먼트에 다음과 같은 옵션들을 전달할 수 있습니다:

- `Target`: 같은 프로젝트에 있는 타겟을 의존성으로 선언합니다.
- `Project`: 다른 프로젝트에 있는 타겟을 의존성으로 선언합니다.
- `Framework`: 바이너리 프레임워크에 대한 의존성을 선언합니다.
- `Library`: 바이너리 라이브러리에 대한 의존성을 선언합니다.
- `XCFramework`: 바이너리 XCFramework에 대한 의존성을 선언합니다.
- `SDK`: 시스템 SDK에 대한 의존성을 선언합니다.
- `XCTest`: XCTest에 대한 의존성을 선언합니다.

> [!NOTE] 의존성 조건
> 모든 의존성 유형은 플랫폼에 따라 의존성을 조건부로 연결하기 위한 `condition` 옵션을 허용합니다. 기본적으로, 타겟이 지원하는 모든 플랫폼에 대해 의존성이 연결됩니다.

> [!TIP] 명시적 의존성 강제하기
> Xcode에서 명시적 의존성을 강제하는 실험적 기능이 있습니다. 타겟이 명시적으로 선언한 의존성만 import할 수 있도록 이 기능을 활성화하는 것을 권장합니다.
>
> ```swift
> import ProjectDescription
> let config = Config(generationOptions: .options(enforceExplicitDependencies: true))
> ```

<!-- > Warning: We haven't yet solved the problem of targets being able to import dependencies that they shouldn't. Some users have implemented their custom solutions to detect this, but we haven't yet found a solution that we're happy with. We are currently exploring customizing the directory where products are outputted to solve this problem. -->

## 외부 의존성 {#external-dependencies}

Tuist는 프로젝트에서 외부 의존성을 선언할 수 있습니다.

### Swift Packages {#swift-packages}

Swift Packages는 프로젝트에서 의존성을 선언하는 권장 방법입니다.
Xcode의 기본 통합 메커니즘을 사용하거나 Tuist의 XcodeProj 기반 통합을 통해 이를 통합할 수 있습니다.

#### Tuist의 XcodeProj 기반 통합 {#tuists-xcodeprojbased-integration}

Xcode의 기본 통합이 가장 편리하긴 하지만, 중간 규모 및 대형 프로젝트에서 필요한 유연성과 제어 기능이 부족합니다.
이를 극복하기 위해 Tuist는 XcodeProj 기반 통합을 제공하여 XcodeProj의 target을 사용해 프로젝트에 Swift 패키지를 통합할 수 있도록 합니다.
덕분에 통합을 더 잘 제어할 수 있을 뿐만 아니라, <LocalizedLink href="/guides/develop/build/cache">caching</LocalizedLink> 및 <LocalizedLink href="/guides/develop/test/smart-runner">smart test runs</LocalizedLink>과 같은 워크플로우와도 호환되도록 만들 수 있습니다.

XcodeProj의 통합은 새로운 Swift Package 기능을 지원하거나 더 많은 Package 구성을 처리하는데 시간이 더 걸릴 가능성이 큽니다. 하지만 Swift Packages와 XcodeProj target 간의 매핑 로직은 오픈소스이며, 커뮤니티에서 기여할 수 있습니다. 이는 Apple이 관리하는 비공개 소스인 Xcode의 기본 통합 방식과는 대조됩니다.

외부 의존성을 추가하려면 `Tuist/` 디렉터리나 프로젝트 루트에 `Package.swift` 파일을 생성해야 합니다.

::: code-group

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),

    ]
)
```

:::

> [!TIP] PACKAGE SETTINGS
> 컴파일러 지시문으로 감싼 `PackageSettings` 인스턴스를 통해 패키지 통합 방식을 설정할 수 있습니다. 예를 들어, 위 예시에서는 packages에 사용되는 기본 product type을 재정의하는 데 사용됩니다. 기본적으로는, 필요하지 않을 것입니다.

`Package.swift` 파일은 외부 의존성을 선언하기 위한 인터페이스일 뿐, 그 외의 역할은 하지 않습니다. 그래서 package에는 target이나 product를 정의하지 않습니다. 의존성을 정의한 후에는, 다음 명령어를 실행하여 의존성을 `Tuist/Dependencies` 디렉터리에 설정하고 가져올 수 있습니다.

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

눈치채셨겠지만, 저희는 [CocoaPods](https://cocoapods.org)'처럼 의존성 해석을 별도의 명령어로 분리하는 방식을 채택했습니다. 이렇게 하면 사용자가 원하는 시점에 의존성을 해석하고 업데이트할 수 있으며, Xcode에서 프로젝트를 열었을 때 바로 컴파일할 수 있는 상태가 됩니다. 이는 프로젝트가 커질수록 Apple이 제공하는 Swift Package Manager 통합 방식에서 개발자 경험이 저하되는 부분입니다.

프로젝트의 타겟에서 `TargetDependency.external` 의존성 타입을 사용하여 이러한 의존성을 참조할 수 있습니다:

::: code-group

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```

:::

> [!NOTE] 외부 패키지에 대한 scheme이 생성되지 않음
> Swift Package 프로젝트의 scheme 목록을 깔끔하게 유지하기 위해 **scheme**이 자동으로 생성되지 않습니다. Xcode의 UI를 통해 생성할 수 있습니다.

#### Xcode의 기본 통합 {#xcodes-default-integration}

If you want to use Xcode's default integration mechanism, you can pass the list `packages` when instantiating a project:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

And then reference them from your targets:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

For Swift Macros and Build Tool Plugins, you'll need to use the types `.macro` and `.plugin` respectively.

> [!WARNING] SPM Build Tool Plugins
> SPM build tool plugins must be declared using [Xcode's default integration](#xcode-s-default-integration) mechanism, even when using Tuist's [XcodeProj-based integration](#tuist-s-xcodeproj-based-integration) for your project dependencies.

A practical application of an SPM build tool plugin is performing code linting during Xcode's "Run Build Tool Plug-ins" build phase. In a package manifest this is defined as follows:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

To generate an Xcode project with the build tool plugin intact, you must declare the package in the project manifest's `packages` array, and then include a package with type `.plugin` in a target's dependencies.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

Since [Carthage](https://github.com/carthage/carthage) outputs `frameworks` or `xcframeworks`, you can run `carthage update` to output the dependencies in the `Carthage/Build` directory and then use the `.framework` or `.xcframework` target dependency type to declare the dependency in your target. You can wrap this in a script that you can run before generating the project.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING] BUILD AND TEST
> If you build and test your project through `tuist build` and `tuist test`, you will similarly need to ensure that the Carthage-resolved dependencies are present by running the `carthage update` command before `tuist build` or `tuist test` are run.

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) expects an Xcode project to integrate the dependencies. You can use Tuist to generate the project, and then run `pod install` to integrate the dependencies by creating a workspace that contains your project and the Pods dependencies. You can wrap this in a script that you can run before generating the project.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods dependencies are not compatible with workflows like `build` or `test` that run `xcodebuild` right after generating the project. They are also incompatible with binary caching and selective testing since the fingerprinting logic doesn't account for the Pods dependencies.

## Static or dynamic {#static-or-dynamic}

Frameworks and libraries can be linked either statically or dynamically, **a choice that has significant implications for aspects like app size and boot time**. Despite its importance, this decision is often made without much consideration.

The **general rule of thumb** is that you want as many things as possible to be statically linked in release builds to achieve fast boot times, and as many things as possible to be dynamically linked in debug builds to achieve fast iteration times.

The challenge with changing between static and dynamic linking in a project graph is that is not trivial in Xcode because a change has cascading effect on the entire graph (e.g. libraries can't contain resources, static frameworks don't need to be embedded). Apple tried to solve the problem with compile time solutions like Swift Package Manager's automatic decision between static and dynamic linking, or [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). However, this adds new dynamic variables to the compilation graph, adding new sources of non-determinism, and potentially causing some features like Swift Previews that rely on the compilation graph to become unreliable.

Luckily, Tuist conceptually compresses the complexity associated with changing between static and dynamic and synthesizes <LocalizedLink href="/guides/develop/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink> that are standard across linking types. In combination with <LocalizedLink href="/guides/develop/projects/dynamic-configuration">dynamic configurations via environment variables</LocalizedLink>, you can pass the linking type at invocation time, and use the value in your manifests to set the product type of your targets.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Note that Tuist <LocalizedLink href="/guides/develop/projects/cost-of-convenience">does not default to convenience through implicit configuration due to its costs</LocalizedLink>. What this means is that we rely on you setting the linking type and any additional build settings that are sometimes required, like the [`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), to ensure the resulting binaries are correct. Therefore, the stance that we take is providing you with the resources, usually in the shape of documentation, to make the right decisions.

> [!TIP] EXAMPLE: COMPOSABLE ARCHITECTURE
> A Swift Package that many projects integrate is [Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture). As described [here](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) and the [troubleshooting section](#troubleshooting), you'll need to set the `OTHER_LDFLAGS` build setting to `$(inherited) -ObjC` when linking the packages statically, which is Tuist's default linking type. Alternatively, you can override the product type for the package to be dynamic.

### Scenarios {#scenarios}

There are some scenarios where setting the linking entirely to static or dynamic is not feasible or a good idea. The following is a non-exhaustive list of scenarios where you might need to mix static and dynamic linking:

- **Apps with extensions:** Since apps and their extensions need to share code, you might need to make those targets dynamic. Otherwise, you'll end up with the same code duplicated in both the app and the extension, causing the binary size to increase.
- **Pre-compiled external dependencies:** Sometimes you are provided with pre-compiled binaries that are either static or dynamic. Static can binaries can be wrapped in dynamic frameworks or libraries to be linked dynamically.

When making changes to the graph, Tuist will analyze it and display a warning if it detects a "static side effect". This warning is meant to help you identify issues that might arise from linking a target statically that depends transitively on a static target through dynamic targets. These side effects often manifest as increased binary size or, in the worst cases, runtime crashes.

## Troubleshooting {#troubleshooting}

### Objective-C Dependencies {#objectivec-dependencies}

When integrating Objective-C dependencies, the inclusion of certain flags on the consuming target may be necessary to avoid runtime crashes as detailed in [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Since the build system and Tuist have no way of inferring whether the flag is necessary or not, and since the flag comes with potentially undesirable side effects, Tuist will not automatically apply any of these flags, and because Swift Package Manager considers `-ObjC` to be included via an `.unsafeFlag` most packages cannot include it as part of their default linking settings when required.

Consumers of Objective-C dependencies (or internal Objective-C targets) should apply `-ObjC` or `-force_load` flags when required by setting `OTHER_LDFLAGS` on consuming targets.

### Firebase & Other Google Libraries {#firebase-other-google-libraries}

Google's open source libraries — while powerful — can be difficult to integrate within Tuist as they often use non-standard architecture and techniques in how they are built.

Here are a few tips that may be necessary to follow to integrate Firebase and Google's other Apple-platform libraries:

#### Ensure `-ObjC` is added to `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Many of Google's libraries are written in Objective-C. Because of this, any consuming target will need to include the `-ObjC` tag in its `OTHER_LDFLAGS` build setting. This can either be set in an `.xcconfig` file or manually specified in the target's settings within your Tuist manifests. An example:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Refer to the [Objective-C Dependencies](#objective-c-dependencies) section above for more details.

#### Set the product type for `FBLPromises` to dynamic framework {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Certain Google libraries depend on `FBLPromises`, another of Google's libraries. You may encounter a crash that mentions `FBLPromises`, looking something like this:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Explicitly setting the product type of `FBLPromises` to `.framework` in your `Package.swift` file should fix the issue:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FPLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### Transitive static dependencies leaking through `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

When a dynamic framework or library depends on static ones through `import StaticSwiftModule`, the symbols are included in the `.swiftmodule` of the dynamic framework or library, potentially [causing the compilation to fail](https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1). To prevent that, you'll have to import the static dependency using [`@_implementationOnly`](https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly):

```swift
@_implementationOnly import StaticModule
```
