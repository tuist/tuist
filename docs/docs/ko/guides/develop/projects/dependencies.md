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

## 외부 의존성 {#external-dependencies}

Tuist는 프로젝트에서 외부 의존성을 선언할 수 있습니다.

### Swift Packages {#swift-packages}

Swift Packages는 프로젝트에서 의존성을 선언하는 권장 방법입니다.
Xcode의 기본 통합 메커니즘을 사용하거나 Tuist의 XcodeProj 기반 통합을 통해 이를 통합할 수 있습니다.

#### Tuist의 XcodeProj 기반 통합 {#tuists-xcodeprojbased-integration}

Xcode의 기본 통합이 가장 편리하긴 하지만, 중간 규모 및 대형 프로젝트에서 필요한 유연성과 제어 기능이 부족합니다.
이를 극복하기 위해 Tuist는 XcodeProj 기반 통합을 제공하여 XcodeProj의 target을 사용해 프로젝트에 Swift 패키지를 통합할 수 있도록 합니다.
덕분에, 통합에 대한 더 많은 제어를 제공할 뿐만 아니라, <LocalizedLink href="/guides/develop/build/cache">캐싱</LocalizedLink> 및 <LocalizedLink href="/guides/develop/test/selective-testing">선택적 테스트 수행</LocalizedLink>과 같은 워크플로우와도 호환될 수 있습니다.

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
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
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

Xcode의 기본 통합 메커니즘을 사용하려면 프로젝트를 생성할 때 `packages` 목록을 전달하면 됩니다:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

그런 다음 target에서 참조하면 됩니다.

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Swift Macro와 Build Tool Plugin의 경우 각각 `.macro`와 `.plugin` type을 사용해야 합니다.

> [!WARNING] SPM Build Tool Plugins
> Tuist의 [XcodeProj 기반 통합](#tuist-s-xcodeproj-based-integration)을 사용해 프로젝트의 의존성을 관리하더라도, SPM build tool plugin은 반드시 [Xcode의 기본 통합](#xcode-s-default-integration) 메커니즘을 통해 선언해야 합니다.

SPM 빌드 도구 플러그인의 실용적인 활용 사례는 Xcode의 'Run Build Tool Plug-ins' Build Phase에서 코드 린팅을 수행하는 것입니다. package manifest에서는 다음과 같이 정의됩니다:

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

build tool plugin이 포함된 Xcode 프로젝트를 생성하려면, 프로젝트 manifest의 `packages` 배열에 package를 선언하고, target의 dependencies에 `.plugin` 타입의 package를 포함해야 합니다.

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

[Carthage](https://github.com/carthage/carthage)는 `frameworks` 또는 `xcframeworks`를 생성하므로, `carthage update` 명령어를 실행해 `Carthage/Build` 디렉토리에 의존성들을 생성한 후, `.framework` 또는 `.xcframework` target dependency type을 사용하여 대상에서 의존성을 선언할 수 있습니다. 이 과정을 다음과 같이 스크립트로 작성하여 프로젝트 생성 전에 실행할 수 있습니다.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING] 빌드 및 테스트
> `tuist build`와 `tuist test`를 통해 프로젝트를 빌드하고 테스트하는 경우, `tuist build` 또는 `tuist build`를 실행하기 전에 `carthage update` 명령어를 실행하여 Carthage로 해결된 의존성들이 존재하는지 확인해야 합니다.

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org)은 의존성을 통합하기 위해 Xcode 프로젝트가 필요합니다. Tuist를 사용하여 프로젝트를 생성한 후, `pod install` 명령어를 실행하여 프로젝트와 Pods 의존성이 포함된 workspace를 생성함으로써 의존성을 통합할 수 있습니다. 이 과정을 다음과 같이 스크립트로 작성하여 프로젝트 생성 전에 실행할 수 있습니다.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 의존성은 프로젝트 생성 직후 `xcodebuild`를 실행하는 `build` 또는 `test`와 같은 workflow와 호환되지 않습니다. 또한, Pods 의존성을 fingerprinting logic에서 고려하지 않기 때문에, binary caching 및 selective testing과도 호환되지 않습니다.

## Static or dynamic {#static-or-dynamic}

Framework와 Library는 정적(static) 또는 동적(dynamic)으로 링크할 수 있으며, **이는 앱 크기와 실행 시간과 같은 부분에 크게 영향을 미칩니다.** 이것은 중요한 결정임에도 불구하고, 대부분은 깊이 고려되지 않고 선택됩니다. 이것은 중요한 결정임에도 불구하고, 대부분은 깊이 고려되지 않고 선택됩니다.

**일반적인 규칙**은 빠른 실행 시간을 위해 릴리즈 빌드에서는 최대한 많은 항목을 정적으로 링크하고, 빠른 반복 작업을 위해 디버그 빌드에서는 최대한 많은 항목을 동적으로 링크하는 것입니다.

Xcode에서 프로젝트 그래프의 링크 방식(static <-> dynamic)을 변경하는 것은 전체 그래프에 영향을 미치기 때문에 간단하지 않습니다 (예: 라이브러리는 리소스를 포함할 수 없고, 정적 프레임워크는 임베드가 불필요함). Apple은 Swift Package Manager의 정적 및 동적 링크 자동 결정이나 [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)와 같은 컴파일 타임 솔루션을 통해 이 문제를 해결하려고 했습니다. 그러나, 이는 컴파일 그래프에 새로운 동적 변수들을 추가하여 비결정적 요소를 증가시키며, Swift Previews와 같이 컴파일 그래프에 의존하는 기능들이 불안정해질 가능성을 높입니다.

다행히도, Tuist는 정적 및 동적 링크 간의 변경과 관련된 복잡성을 개념적으로 단순화하고, 링크 타입과 관계없이 표준화된 <LocalizedLink href="/guides/develop/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink>를 생성합니다. <LocalizedLink href="/guides/develop/projects/dynamic-configuration">환경 변수를 통한 동적 구성</LocalizedLink>과 함께 사용하면 호출 시점에 링크 타입을 전달할 수 있으며, 이 값을 manifest에서 사용해 target의 product 타입을 설정할 수 있습니다.

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

Tuist는 <LocalizedLink href="/guides/develop/projects/cost-of-convenience">비용 문제로 인해 암시적 구성(implicit configuration)을 통한 편의성을 기본값으로 제공하지 않는 점</LocalizedLink>을 참고하세요. 이는 최종 바이너리가 올바르게 생성되기 위해 사용자가 직접 링크 타입과 [`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) 같은 추가 빌드 설정을 해야한다는 뜻입니다. 따라서, 우리는 주로 문서 형태의 자료를 제공하여 사용자가 올바른 결정을 내릴 수 있도록 돕는 방식을 취하고 있습니다.

> [!TIP] 예시: COMPOSABLE ARCHITECTURE
> 많은 프로젝트에서 사용하는 Swift Package로는 [Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)가 있습니다. [여기](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)와 [troubleshooting section](#troubleshooting)에 설명된 대로, package를 정적으로 링크할 때는 `OTHER_LDFLAGS` 빌드 설정을 `$(inherited) -ObjC`로 설정해야 합니다. Tuist의 기본 링크 방식이 정적 링크이기 때문입니다. 다른 방법으로는, package의 product type을 동적으로 override할 수 있습니다.

### 시나리오 {#scenarios}

링크 방식을 전부 정적 또는 동적으로만 설정하는 것이 불가능하거나 적절하지 않은 경우가 있습니다. 다음은 정적 및 동적 링크를 혼합해야 할 수 있는 상황들의 예입니다:

- **확장 기능이 포함된 앱:** 앱과 확장 기능이 코드를 공유해야 하기 때문에, target들을 동적으로 만들어야할 수 있습니다. 그렇지 않으면, 동일한 코드가 앱과 확장 기능 모두에 중복되어 바이너리 크기가 커지게 됩니다.
- **사전에 컴파일된 외부 의존성**: 때로는 정적 또는 동적으로 미리 컴파일된 바이너리가 제공되기도 합니다. 정적 바이너리는 동적으로 링크하기 위해 동적 프레임워크나 라이브러리로 감쌀 수 있습니다.

그래프를 변경할 때, Tuist는 이를 분석하여 "static side effect"를 감지하면 경고를 표시합니다. 이 경고는 동적 target을 통해 정적 target에 전이적으로 의존하는 target을 정적으로 링크할 때 발생할 수 있는 문제를 식별하는 데 도움을 줍니다. 이러한 side effect는 종종 바이너리 크기 증가로 나타나거나, 최악의 경우 런타임 크래시가 발생할 수 있습니다.

## 문제 해결 {#troubleshooting}

### Objective-C 의존성 {#objectivec-dependencies}

Objective-C 의존성을 통합할 때, [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)에서 자세히 설명된 대로 런타임 크래시를 방지하기 위해 사용하는 target에 특정 flag를 포함해야 할 수 있습니다.

빌드 시스템과 Tuist는 flag가 필요한지여부를 추론할 수 없고, 이 flag가 잠재적으로 원치 않는 side effect를 발생시킬 수 있기 때문에, Tuist는 이러한 플래그들을 자동으로 적용하지 않습니다. 또한, Swift Package Manager는 `-ObjC`를 `.unsafeFlag`를 통해 포함되는 것으로 간주하기 때문에, 대부분의 package는 필요한 경우에도 이를 기본 링크 설정의 일부로 포함할 수 없습니다.

Objective-C 의존성(또는 내부 Objective-C target)을 사용하는 target은 필요할 경우 `OTHER_LDFLAGS`에 `-ObjC` 또는 `-force_load` flag를 설정하여 적용해야 합니다.

### Firebase & Other Google Libraries {#firebase-other-google-libraries}

Google의 오픈 소스 라이브러리는 강력하지만, 종종 일반적이지 않은 아키텍처와 기술로 빌드되기 때문에 Tuist에 통합하기 어려울 수 있습니다.

다음은 Firebase와 Google의 다른 Apple 플랫폼 라이브러리들을 통합하기 위해 필요할 수 있는 몇 가지 팁입니다:

#### `OTHER_LDFLAGS`에 `-ObjC`가 추가되었는지 확인하세요 {#ensure-objc-is-added-to-other_ldflags}

Google의 라이브러리 중 다수는 Objective-C로 작성되어 있습니다. 이로 인해, 사용하는 모든 target은 `OTHER_LDFLAGS` 빌드 설정에 `-ObjC` flag를 포함해야 합니다. 이는 `.xcconfig` 파일에서 설정하거나 Tuist manifest 파일에서 내의 target 설정에서 직접 지정할 수 있습니다. 예시:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

자세한 내용은 [Objective-C Dependencies](#objective-c-dependencies) 섹션을 참고하세요.

#### `FBLPromises` product type을 동적 프레임워크로 설정하기 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

일부 Google 라이브러리는 Google의 또 다른 라이브러리인 `FBLPromises`에 의존합니다. `FBLPromises`와 관련된 다음과 같은 크래시가 발생할 수 있습니다:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` 파일에서 `FBLPromises`의 product type을 `.framework`로 명시적으로 설정하면 이 문제가 해결될 것입니다:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### `.swiftmodule`에서 발생하는 전이적 정적 의존성 문제 {#transitive-static-dependencies-leaking-through-swiftmodule}

When a dynamic framework or library depends on static ones through `import StaticSwiftModule`, the symbols are included in the `.swiftmodule` of the dynamic framework or library, potentially <LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">causing the compilation to fail</LocalizedLink>. To prevent that, you'll have to import the static dependency using <LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink>:

```swift
internal import StaticModule
```

> [!NOTE]
> Access level on imports was included in Swift 6. If you're using older versions of Swift, you need to use <LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink> instead:

```swift
@_implementationOnly import StaticModule
```
