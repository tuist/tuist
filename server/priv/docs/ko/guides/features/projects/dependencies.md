---
{
  "title": "의존성",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 프로젝트에서 의존성을 선언하는 방법을 알아보세요."
}
---
# 의존성 {#dependencies}

프로젝트가 커지면 코드 공유, 경계 정의, 빌드 시간 개선을 위해 여러 타겟으로 나누는 것이 일반적입니다. 여러 타겟을 사용하면 타겟 간 의존성을 정의하여 **의존성 그래프**를 형성하게 되며, 여기에는 외부 의존성도 포함될 수 있습니다.

## XcodeProj로 코딩된 그래프 {#xcodeprojcodified-graphs}

Xcode와 XcodeProj의 설계 특성상, 의존성 그래프를 유지 관리하는 작업은 지루하고 실수가 발생하기 쉽습니다. 다음과 같은 문제를 겪을 수 있습니다.

- Xcode의 빌드 시스템은 프로젝트의 모든 제품을 Derived Data의 동일한 디렉터리에 출력하므로, 타겟이 가져오면 안 되는 제품을 가져올 수 있습니다. 클린 빌드가 더 일반적인 CI 환경이나 나중에 다른 구성을 사용할 때 컴파일이 실패할 수 있습니다.
- 타겟의 전달적 동적 의존성은 `LD_RUNPATH_SEARCH_PATHS` 빌드 설정에 포함된 디렉터리 중 하나로 복사되어야 합니다. 그렇지 않으면 런타임에 타겟이 해당 의존성을 찾지 못합니다. 그래프가 작을 때는 쉽게 생각하고 설정할 수 있지만, 그래프가 커지면 문제가 됩니다.
- 타겟이 정적 [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)을 링크하면, Xcode가 번들을 처리하고 현재 플랫폼 및 아키텍처에 맞는 올바른 바이너리를 추출하도록 추가 빌드 단계가 필요합니다. 이 빌드 단계는 자동으로 추가되지 않으며, 추가하는 것을 잊기 쉽습니다.

위 내용은 몇 가지 예시에 불과하지만, 그동안 우리가 마주한 문제는 훨씬 더 많습니다. 의존성 그래프를 유지 관리하고 유효성을 보장하기 위해 엔지니어 팀이 필요하다고 상상해 보세요. 또는 더 나쁘게는, 제어하거나カスタ마이즈할 수 없는 폐쇄형 소스 빌드 시스템이 빌드 시간에 이러한 복잡성을 해결한다고 가정해 보세요. 익숙하지 않나요? 이는 Apple이 Xcode와 XcodeProj에서 채택했고 Swift Package Manager가 계승한 접근 방식입니다.

저희는 의존성 그래프가 **명시적**이고 **정적**이어야 한다고 강력히 믿습니다. 그래야만 **유효성 검사**와 **최적화**가 가능하기 때문입니다. Tuist를 사용하면 무엇이 무엇에 의존하는지 설명하는 데 집중하면 되고, 나머지는 저희가 처리합니다. 복잡한 구현 세부 사항은 여러분에게서 추상화됩니다.

다음 섹션에서는 프로젝트에서 의존성을 선언하는 방법을 알아봅니다.

> [!TIP]
> **그래프 유효성 검사**
>
> Tuist는 프로젝트 생성 시 그래프에 순환이 없고 모든 의존성이 유효한지 확인하기 위해 그래프를 검증합니다. 덕분에 어떤 팀이든 의존성 그래프를 깨뜨릴 걱정 없이 진화에 참여할 수 있습니다.


## 로컬 의존성 {#local-dependencies}

타겟은 동일 프로젝트 내 또는 다른 프로젝트의 다른 타겟과 바이너리에 의존할 수 있습니다. `Target` 인스턴스를 생성할 때 `dependencies` 인수를 다음 옵션 중 하나로 전달할 수 있습니다.

- `Target`: 동일 프로젝트 내의 타겟과의 의존성을 선언합니다.
- `Project`: 다른 프로젝트의 타겟과의 의존성을 선언합니다.
- `Framework`: 바이너리 프레임워크와의 의존성을 선언합니다.
- `Library`: 바이너리 라이브러리와의 의존성을 선언합니다.
- `XCFramework`: 바이너리 XCFramework와의 의존성을 선언합니다.
- `SDK`: 시스템 SDK와의 의존성을 선언합니다.
- `XCTest`: XCTest와의 의존성을 선언합니다.
- `Macro`: 동일 프로젝트에 정의된 Swift 매크로 타겟과의 의존성을 선언합니다([Swift Macros](#swift-macros) 참조).

> [!NOTE]
> **의존성 조건**
>
> 모든 의존성 유형은 플랫폼에 따라 조건부로 의존성을 링크하기 위한 `condition` 옵션을 허용합니다. 기본적으로 타겟이 지원하는 모든 플랫폼에 대해 의존성을 링크합니다.


## 외부 의존성 {#external-dependencies}

Tuist는 프로젝트에서 외부 의존성을 선언할 수도 있습니다.

### Swift Packages {#swift-packages}

Swift Packages는 프로젝트에서 의존성을 선언하는 데 권장되는 방법입니다. Xcode의 기본 통합 메커니즘을 사용하거나 Tuist의 XcodeProj 기반 통합을 사용하여 통합할 수 있습니다.

#### Tuist의 XcodeProj 기반 통합 {#tuists-xcodeprojbased-integration}

Xcode의 기본 통합은 가장 편리하지만, 중대규모 프로젝트에 필요한 유연성과 제어 기능이 부족합니다. 이를 극복하기 위해 Tuist는 XcodeProj의 타겟을 사용하여 프로젝트에 Swift Packages를 통합할 수 있는 XcodeProj 기반 통합을 제공합니다. 이를 통해 통합에 대한 제어 권한을 더 제공할 뿐만 아니라 <.localized_link href="/guides/features/cache">캐싱</.localized_link> 및 <.localized_link href="/guides/features/selective-testing">선택적 테스트 실행</.localized_link>과 같은 워크플로와 호환되도록 만들 수 있습니다.

XcodeProj 통합은 새로운 Swift Package 기능을 지원하거나 더 많은 패키지 구성을 처리하는 데 시간이 더 걸릴 가능성이 높습니다. 그러나 Swift Packages와 XcodeProj 타겟 간의 매핑 로직은 오픈 소스이며 커뮤니티가 기여할 수 있습니다. 이는 폐쇄형 소스이며 Apple이 유지 관리하는 Xcode의 기본 통합과 대조적입니다.

외부 의존성을 추가하려면 `Package.swift` 파일을 `Tuist/` 아래 또는 프로젝트 루트에 생성해야 합니다.

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
<!-- -->
:::

> [!TIP]
> **패키지 설정**
>
> 컴파일러 지시어로 감싸진 `PackageSettings` 인스턴스를 사용하면 패키지가 통합되는 방식을 구성할 수 있습니다. 예를 들어, 위 예제에서는 패키지에 사용되는 기본 제품 유형을 재정의하는 데 사용됩니다. 기본적으로는 이것이 필요하지 않습니다. 또한 `expectedSignatures`를 통해 SwiftPM 바이너리 타겟에 대한 예상 서명을 구성하는 데 사용할 수도 있습니다.


### 바이너리 타겟 서명

로컬 또는 원격 Swift 패키지가 바이너리 XCFramework 타겟을 노출하는 경우, `PackageSettings.expectedSignatures`를 사용하여 예상 서명을 구성할 수 있습니다.

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> 프로젝트가 표준 `Debug` 및 `Release` 이외의 사용자 지정 빌드 구성을 사용하는 경우, `PackageSettings`에서 `baseSettings`를 사용하여 이를 지정해야 합니다. 외부 의존성은 올바르게 빌드되기 위해 프로젝트의 구성을 알아야 합니다. 예를 들면 다음과 같습니다.
>
> ```swift
> #if TUIST
>     import ProjectDescription
>
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
>
> 자세한 내용은 [#8345](https://github.com/tuist/tuist/issues/8345)를 참조하세요.

`Package.swift` 파일은 외부 의존성을 선언하기 위한 인터페이스일 뿐이며 그 이상은 아닙니다. 따라서 패키지에서 타겟이나 제품을 정의하지 않습니다. 의존성을 정의한 후에는 다음 명령을 실행하여 의존성을 해결하고 `Tuist/Dependencies` 디렉터리로 가져올 수 있습니다.

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

알다시피, [CocoaPods](https://cocoapods.org)와 유사한 접근 방식을 취하며, 의존성 해결은 별도의 명령어로 수행됩니다. 이를 통해 사용자는 의존성을 언제 해결하고 업데이트할지 제어할 수 있으며, 프로젝트를 Xcode에서 열어 바로 컴파일할 수 있도록 준비된 상태로 유지할 수 있습니다. 프로젝트가 커질수록 Apple의 Swift Package Manager 통합이 제공하는 개발자 경험이 저하된다고 생각합니다.

프로젝트 타겟에서 `TargetDependency.external` 의존성 유형을 사용하여 해당 의존성을 참조할 수 있습니다.

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
            bundleId: "dev.tuist.app",
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
<!-- -->
:::

> [!NOTE]
> **외부 패키지에 대한 스킴 생성 안 함**
>
> 스킴 목록을 깔끔하게 유지하기 위해 Swift Package 프로젝트에 대해 **스킴**이 자동으로 생성되지 않습니다. Xcode UI를 통해 직접 생성할 수 있습니다.


#### Xcode의 기본 통합 {#xcodes-default-integration}

Xcode의 기본 통합 메커니즘을 사용하려면, 프로젝트를 인스턴스화할 때 `packages` 목록을 전달하면 됩니다.

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

그런 다음 타겟에서 이를 참조합니다.

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Xcode의 기본 통합을 통해 외부 Swift Package에서 Swift Macro 또는 Build Tool Plugin을 통합할 때는 각각 `.macro` 및 `.plugin` 유형으로 선언하세요. 매크로는 [Tuist의 XcodeProj 기반 통합](#tuists-xcodeprojbased-integration)을 통해서도 사용할 수 있으며, 패키지에서 가져오는 대신 자체 Swift 매크로를 정의하려면 [Swift Macros](#swift-macros)를 참조하세요.

> [!WARNING]
> **SPM 빌드 도구 플러그인**
>
> 프로젝트 의존성에 Tuist의 [XcodeProj 기반 통합](#tuists-xcodeprojbased-integration)을 사용하더라도, SPM 빌드 도구 플러그인은 [Xcode의 기본 통합](#xcodes-default-integration) 메커니즘을 사용하여 선언해야 합니다.

SPM 빌드 도구 플러그인은 타겟에 대해 실행해야 할 구체적인 빌드 명령을 발견하기 위해 Xcode와 SwiftPM이 실행하는 Swift 프로그램입니다. 이러한 명령은 패키지 그래프, 타겟 파일, 플러그인 작업 디렉터리, 해결된 플러그인 도구, 그리고 플러그인이 선언한 출력물에 의존할 수 있습니다. 일부 플러그인은 동일한 타겟 빌드의 일부가 되어야 하는 파일을 생성하기도 합니다.

Tuist의 XcodeProj 기반 통합은 매핑이 정적인 경우(예: 라이브러리, 바이너리, 실행 파일, 매크로) 패키지 제품을 네이티브 Xcode 타겟으로 매핑합니다. 빌드 도구 플러그인은 Xcode의 SwiftPM 통합 외부에 해당하는 네이티브 Xcode 프로젝트 프리미티브가 없습니다. 플러그인이 결국 실행 파일을 실행할 수는 있지만, 일반 스크립트 빌드 단계에서 해당 실행 파일을 호출하는 것은 플러그인을 실행하는 것과 동일하지 않습니다. Tuist는 먼저 플러그인의 Swift 코드를 평가하고, SwiftPM의 플러그인 컨텍스트를 재현하며, 명령을 발견하고, 선언된 입력과 출력을 모델링한 후, Xcode가 빌드를 계획하기 전에 생성된 모든 파일을 타겟 그래프에 추가해야 합니다.

이러한 이유로, `Tuist/Package.swift`에서만 플러그인 패키지를 선언하고 `.external(name:)`를 통해 사용하는 것은 지원되지 않습니다. 대신 지원되는 방법은 `Project.packages`에 패키지를 선언하고 `.package(product:type: .plugin)`를 사용하여 소비하는 타겟에 플러그인 제품을 추가하는 것입니다. 이렇게 하면 플러그인이 Swift Package 제품 의존성으로서 생성된 Xcode 프로젝트에 연결되므로, Xcode와 SwiftPM이 네이티브 플러그인 컨텍스트로 이를 실행할 수 있습니다.

단점은 해당 플러그인 통합을 Xcode가 소유한다는 점입니다.

- Xcode는 SwiftPM 통합을 통해 플러그인 패키지를 해결하고 빌드합니다.
- 패키지는 Tuist가 생성한 외부 타겟 대신 Swift Package 참조로서 생성된 프로젝트에 나타납니다.
- Tuist는 정적으로 매핑된 패키지 제품에 제공할 수 있는 수준의 제어, 검증, 캐싱 및 선택적 테스팅 동작을 플러그인에 제공하지 못합니다.
- CI 및 로컬 빌드는 해당 플러그인 패키지에 대해 Xcode의 패키지 해결을 허용해야 합니다.

이러한 함의 때문에 Tuist 프로젝트에서 SPM 빌드 도구 플러그인을 사용하는 것은 일반적으로 권장하지 않습니다. 가능한 경우 타겟에 선언된 빌드 단계 스크립트를 선호하거나, Tuist 또는 Xcode를 호출하기 전에 생성된 Xcode 프로젝트 외부의 스크립트에서 도구를 실행하세요.

SPM 빌드 도구 플러그인의 실제 적용 사례 중 하나는 Xcode의 "Run Build Tool Plug-ins" 빌드 단계 동안 코드 린팅을 수행하는 것입니다. 빌드 도구 플러그인이 포함된 Xcode 프로젝트를 생성하려면 프로젝트 매니페스트의 `packages` 배열에 패키지를 선언한 후, 타겟의 의존성에 `.plugin` 유형의 패키지를 포함시키세요.

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

[Carthage](https://github.com/carthage/carthage)는 `frameworks` 또는 `xcframeworks`를 출력하므로, `carthage update`를 실행하여 `Carthage/Build` 디렉터리에 의존성을 출력한 후, `.framework` 또는 `.xcframework` 타겟 의존성 유형을 사용하여 타겟에 의존성을 선언할 수 있습니다. 이를 프로젝트 생성 전에 실행할 수 있는 스크립트로 감쌀 수 있습니다.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **빌드 및 테스트**
>
> `xcodebuild build` 및 `tuist test`를 통해 프로젝트를 빌드하고 테스트하는 경우, 빌드 또는 테스트 전에 `carthage update` 명령을 실행하여 Carthage로 해결된 의존성이 존재하도록 해야 합니다.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org)는 의존성을 통합하기 위해 Xcode 프로젝트를 필요로 합니다. Tuist를 사용하여 프로젝트를 생성한 후, `pod install`를 실행하여 프로젝트와 Pods 의존성을 포함하는 워크스페이스를 생성함으로써 의존성을 통합할 수 있습니다. 이를 프로젝트 생성 전에 실행할 수 있는 스크립트로 감쌀 수 있습니다.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 의존성은 프로젝트 생성 직후 `xcodebuild`를 실행하는 `build` 또는 `test`와 같은 워크플로와 호환되지 않습니다. 또한 핑거프린팅 로직이 Pods 의존성을 고려하지 않기 때문에 바이너리 캐싱 및 선택적 테스팅과도 호환되지 않습니다.


## Swift Macros {#swift-macros}

Tuist 프로젝트에서 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)를 사용할 때 두 가지 distinct 시나리오가 있으며, 어느 상황에 있는지 명시하는 것이 중요합니다.

- **외부 Swift Package에 정의된 매크로 사용.** 두 통합 메커니즘 모두 매크로를 지원합니다. [Tuist의 XcodeProj 기반 통합](#tuists-xcodeprojbased-integration)을 사용하면 `Tuist/Package.swift`에 패키지를 선언하고 `.external(name:)`로 의존성을 설정합니다. Tuist는 매크로 제품을 네이티브 타겟으로 매핑합니다. [Xcode의 기본 통합](#xcodes-default-integration)을 사용하면 `.package(product:type: .macro)`로 의존성을 선언합니다. 빌드 도구 플러그인과 달리 매크로는 Xcode의 기본 통합으로 제한되지 않습니다.
- 프로젝트의 일부로 **자체 매크로 정의** — 예를 들어 모노레포 내의 공유 라이브러리에서. 이를 위해 `Package.swift`가 필요하지 않습니다. Tuist는 일급 시민인 `.macro` 제품 유형을 제공하므로 매니페스트에서 매크로 타겟을 직접 선언할 수 있습니다.

### 자체 매크로 정의 {#defining-your-own-macro}

Swift 매크로는 컴파일러 플러그인입니다. 즉, Swift 컴파일러가 컴파일 시간에 로드하고 실행하는 실행 파일입니다. Tuist는 이를 `.macro` 제품 유형으로 네이티브하게 모델링합니다. Apple은 Xcode 프로젝트에서 Swift Macro 타겟 유형을 노출하지 않지만, Tuist는 명령줄 도구 타겟을 생성하고 이를 매크로를 사용하는 타겟의 의존성으로 연결하며 Swift 컴파일러 설정에 `-load-plugin-executable` 플래그를 주입함으로써 이를 가능하게 합니다. 이러한 모든 연결 작업은 자동으로 처리됩니다.

일반적인 매크로는 두 개의 타겟으로 나뉩니다. 매크로를 구현하는 **플러그인** 타겟(`product: .macro`)과 매크로의 공개 인터페이스(`@attached`/`@freestanding` 선언)를 선언하고 `.macro(name:)`를 통해 플러그인에 의존하는 **라이브러리** 타겟입니다. 플러그인은 빌드 머신에서 실행되므로 해당 타겟은 호스트 전용(macOS)입니다.

매크로 구현은 [swift-syntax](https://github.com/swiftlang/swift-syntax)에 의존하며, 이는 `Tuist/Package.swift`에서 일반 외부 의존성으로 선언합니다.

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

그런 다음 프로젝트에서 매크로 플러그인 및 라이브러리 타겟을 직접 정의할 수 있습니다.

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

`MyLibrary`를 링크하는 모든 타겟은 이제 매크로를 사용할 수 있습니다. Tuist는 컴파일러가 플러그인을 로드할 수 있도록 플러그인을 전파합니다.


## 정적 또는 동적 {#static-or-dynamic}

프레임워크와 라이브러리는 정적으로 또는 동적으로 링크할 수 있으며, **이 선택은 앱 크기 및 부팅 시간과 같은 측면에 상당한 영향을 미칩니다**. 그 중요성에도 불구하고 이 결정은 종종 충분한 고려 없이 내려집니다.

**일반적인 경험 법칙**은 빠른 부팅 시간을 위해 릴리스 빌드에서는 가능한 많은 것을 정적으로 링크하고, 빠른 반복 작업을 위해 디버그 빌드에서는 가능한 많은 것을 동적으로 링크하는 것입니다.

프로젝트 그래프에서 정적 링크와 동적 링크 간 전환의 어려움은 Xcode에서 간단하지 않다는 점입니다. 변경 사항이 전체 그래프에 연쇄적인 영향을 미치기 때문입니다(예: 라이브러리는 리소스를 포함할 수 없고, 정적 프레임워크는 임베드할 필요가 없음). Apple은 Swift Package Manager의 정적 및 동적 링크 간 자동 결정이나 [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)와 같은 컴파일 시간 솔루션으로 이 문제를 해결하려 했습니다. 그러나 이는 컴파일레이션 그래프에 새로운 동적 변수를 추가하여 비결정성의 새로운 원인을 만들고, 컴파일레이션 그래프에 의존하는 Swift Previews와 같은 일부 기능의 신뢰성을 떨어뜨릴 수 있습니다.

다행히 Tuist는 정적 및 동적 간 전환과 관련된 복잡성을 개념적으로 압축하고 링크 유형 전반에 표준인 <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">번들 접근자</.localized_link>를 합성합니다. <.localized_link href="/guides/features/projects/dynamic-configuration">환경 변수를 통한 동적 구성</.localized_link>과 결합하면 호출 시점에 링크 유형을 전달하고 매니페스트에서 해당 값을 사용하여 타겟의 제품 유형을 설정할 수 있습니다.

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

Tuist는 <.localized_link href="/guides/features/projects/cost-of-convenience">비용 때문에 암시적 구성을 통한 편의성을 기본값으로 사용하지 않습니다</.localized_link>. 이는 링크 유형과 때때로 필요한 추가 빌드 설정(예: [`-ObjC` 링커 플래그](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184))을 사용자가 직접 설정하여 결과 바이너리가 올바르도록 해야 함을 의미합니다. 따라서 올바른 결정을 내릴 수 있도록 문서 형태의 리소스를 제공하는 것이 우리의 입장입니다.

> [!TIP]
> **예시: The Composable Architecture**
>
> 많은 프로젝트가 통합하는 Swift Package는 [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)입니다. 자세한 내용은 [이 섹션](#the-composable-architecture)을 참조하세요.


### 시나리오 {#scenarios}

링크를 완전히 정적 또는 동적으로 설정하는 것이 실현 불가능하거나 바람직하지 않은 시나리오가 있습니다. 다음은 정적 및 동적 링크를 혼합해야 할 수 있는 시나리오의 일부 목록입니다.

- **확장 기능이 있는 앱:** 앱과 확장 기능이 코드를 공유해야 하므로 해당 타겟을 동적으로 만들어야 할 수 있습니다. 그렇지 않으면 앱과 확장 기능 모두에 동일한 코드가 중복되어 바이너리 크기가 증가합니다.
- **사전 컴파일된 외부 의존성:** 때로는 정적 또는 동적인 사전 컴파일된 바이너리가 제공됩니다. 정적 바이너리는 동적으로 링크되도록 동적 프레임워크나 라이브러리로 감쌀 수 있습니다.

그래프를 변경할 때 Tuist는 이를 분석하고 "정적 사이드 이펙트"를 감지하면 경고를 표시합니다. 이 경고는 동적 타겟을 통해 정적 타겟에 간접적으로 의존하는 타겟을 정적으로 링크할 때 발생할 수 있는 문제를 식별하는 데 도움이 됩니다. 이러한 사이드 이펙트는 종종 바이너리 크기 증가 또는 최악의 경우 런타임 충돌로 나타납니다.

## 문제 해결 {#troubleshooting}

### Objective-C 의존성 {#objectivec-dependencies}

Objective-C 의존성을 통합할 때, [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)에 자세히 설명된 대로 런타임 충돌을 방지하기 위해 소비 타겟에 특정 플래그를 포함해야 할 수 있습니다.

빌드 시스템과 Tuist는 플래그가 필요한지 여부를 추론할 방법이 없으며, 플래그에는 잠재적으로 바람직하지 않은 사이드 이펙트가 따르기 때문에 Tuist는 이러한 플래그를 자동으로 적용하지 않습니다. 또한 Swift Package Manager는 `-ObjC`를 `.unsafeFlag`를 통해 포함되는 것으로 간주하므로 대부분의 패키지는 필요할 때 기본 링크 설정의 일부로 이를 포함할 수 없습니다.

Objective-C 의존성 소비자(또는 내부 Objective-C 타겟)는 필요시 소비 타겟에 `OTHER_LDFLAGS`를 설정하여 `-ObjC` 또는 `-force_load` 플래그를 적용해야 합니다.

### Firebase 및 기타 Google 라이브러리 {#firebase-other-google-libraries}

Google의 오픈 소스 라이브러리는 강력하지만 빌드 방식에서 비표준 아키텍처와 기술을 자주 사용하기 때문에 Tuist 내에서 통합하기 어려울 수 있습니다.

Firebase와 Google의 다른 Apple 플랫폼 라이브러리를 통합하기 위해 따라야 할 몇 가지 팁은 다음과 같습니다.

#### `-ObjC`가 `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}에 추가되었는지 확인

Google의 많은 라이브러리는 Objective-C로 작성되었습니다. 따라서 모든 소비 타겟은 `OTHER_LDFLAGS` 빌드 설정에 `-ObjC` 태그를 포함해야 합니다. 이는 `.xcconfig` 파일에서 설정하거나 Tuist 매니페스트 내의 타겟 설정에서 직접 지정할 수 있습니다. 예시:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

자세한 내용은 위의 [Objective-C 의존성](#objective-c-dependencies) 섹션을 참조하세요.

#### `FBLPromises`의 제품 유형을 동적 프레임워크로 설정 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

일부 Google 라이브러리는 Google의 또 다른 라이브러리인 `FBLPromises`에 의존합니다. 다음과 같이 `FBLPromises`를 언급하는 충돌이 발생할 수 있습니다:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` 파일에서 `FBLPromises`의 제품 유형을 명시적으로 `.framework`로 설정하면 문제가 해결됩니다:

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

### The Composable Architecture {#the-composable-architecture}

[여기](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)와 [문제 해결 섹션](#troubleshooting)에 설명된 대로, Tuist의 기본 링크 유형인 정적 링크를 사용할 때 `OTHER_LDFLAGS` 빌드 설정을 `$(inherited) -ObjC`로 설정해야 합니다. 대안으로 패키지의 제품 유형을 동적으로 재정의할 수 있습니다. 정적으로 링크할 때 테스트 및 앱 타겟은 일반적으로 문제없이 작동하지만 SwiftUI 미리보기는 깨집니다. 이는 모든 것을 동적으로 링크하여 해결할 수 있습니다. 아래 예제에서는 The Composable Architecture와 함께 자주 사용되며 자체적인 [구성 함정](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)이 있는 [Sharing](https://github.com/pointfreeco/swift-sharing)도 의존성으로 추가되었습니다.

다음 구성은 모든 것을 동적으로 링크하므로 앱 + 테스트 타겟과 SwiftUI 미리보기가 정상적으로 작동합니다.

> [!TIP]
> **정적 또는 동적**
>
> 동적 링크가 항상 권장되는 것은 아닙니다. 자세한 내용은 [정적 또는 동적](#static-or-dynamic) 섹션을 참조하세요. 이 예제에서는 단순성을 위해 모든 의존성이 조건 없이 동적으로 링크됩니다.


```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

> [!WARNING]
> `import Sharing` 대신 `import SwiftSharing`를 사용해야 합니다.


### `.swiftmodule`을 통한 전달적 정적 의존성 누출 {#transitive-static-dependencies-leaking-through-swiftmodule}

동적 프레임워크나 라이브러리가 `import StaticSwiftModule`를 통해 정적 모듈에 의존할 때, 해당 심볼은 동적 프레임워크나 라이브러리의 `.swiftmodule`에 포함되어 컴파일이 실패할 수 있습니다<.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1"></.localized_link>. 이를 방지하려면 <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>를 사용하여 정적 의존성을 가져와야 합니다:

```swift
internal import StaticModule
```

> [!NOTE]
> Swift 6에는 import의 접근 수준이 포함되었습니다. 이전 버전의 Swift를 사용하는 경우 대신 <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>를 사용해야 합니다:


```swift
@_implementationOnly import StaticModule
```
