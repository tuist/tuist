---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# 종속성 {#종속성}

프로젝트가 커지면 코드를 공유하고 경계를 정의하며 빌드 시간을 개선하기 위해 여러 개의 대상으로 분할하는 것이 일반적입니다. 여러 개의 타깃은
외부 종속성을 포함할 수 있는 **종속성 그래프(**)를 형성하는 타깃 간의 종속성을 정의하는 것을 의미합니다.

## XcodeProj 코딩된 그래프 {#xcodeprojcodified-graphs}

Xcode 및 XcodeProj의 디자인으로 인해 종속성 그래프를 유지 관리하는 것은 지루하고 오류가 발생하기 쉬운 작업일 수 있습니다. 다음은
발생할 수 있는 문제의 몇 가지 예입니다:

- Xcode의 빌드 시스템은 프로젝트의 모든 제품을 파생된 데이터의 동일한 디렉터리에 출력하기 때문에 대상에서 가져오지 말아야 할 제품을
  가져올 수 있습니다. 클린 빌드가 더 일반적인 CI에서 컴파일이 실패하거나 나중에 다른 구성을 사용할 때 컴파일이 실패할 수 있습니다.
- 대상의 전이적 동적 종속성은 `LD_RUNPATH_SEARCH_PATHS` 빌드 설정의 일부인 디렉터리에 복사해야 합니다. 그렇지 않으면
  타겟이 런타임에 해당 종속 요소를 찾을 수 없습니다. 그래프가 작을 때는 생각하기 쉽고 설정하기 쉽지만 그래프가 커지면 문제가 됩니다.
- 타겟이 정적
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)를
  링크하는 경우, Xcode가 번들을 처리하고 현재 플랫폼 및 아키텍처에 적합한 바이너리를 추출하기 위해 타겟에 추가 빌드 단계가 필요합니다.
  이 빌드 단계는 자동으로 추가되지 않으므로 추가하는 것을 잊어버리기 쉽습니다.

위의 예는 몇 가지 예에 불과하지만, 수년 동안 우리가 겪은 사례는 훨씬 더 많습니다. 종속성 그래프를 유지하고 그 유효성을 보장하기 위해
엔지니어 팀이 필요하다고 상상해 보세요. 또는 더 나쁜 경우, 제어하거나 사용자 지정할 수 없는 비공개 소스 빌드 시스템에 의해 복잡한 문제가
빌드 시점에 해결된다고 상상해 보세요. 익숙한 이야기인가요? 이것이 바로 Apple이 Xcode와 XcodeProj에서 취했던 접근 방식이며
Swift 패키지 관리자가 이를 계승한 것입니다.

의존성 그래프는 **명시적** 및 **정적** 그래야만 **검증** 및 **최적화** 될 수 있기 때문에, 저희는 의존성 그래프가 명시적이어야
한다고 강력히 믿습니다. Tuist를 사용하면 무엇이 무엇에 의존하는지 설명하는 데 집중하면 나머지는 저희가 알아서 처리합니다. 복잡하고
세부적인 구현은 추상화되어 있습니다.

다음 섹션에서는 프로젝트에서 종속성을 선언하는 방법에 대해 알아보세요.

> [!TIP] 그래프 검증 튜이스트는 프로젝트를 생성할 때 그래프의 유효성을 검사하여 사이클이 없는지, 모든 종속성이 유효한지 확인합니다.
> 덕분에 모든 팀이 종속성 그래프가 깨질 염려 없이 발전하는 데 참여할 수 있습니다.

## 로컬 종속성 {#local-dependencies}

타깃은 동일하거나 다른 프로젝트의 다른 타깃 및 바이너리에 종속될 수 있습니다. ` Target` 을 인스턴스화할 때 다음 옵션 중 하나를
사용하여 `종속성` 인수를 전달할 수 있습니다:

- `대상`: 동일한 프로젝트 내에서 타깃과의 종속성을 선언합니다.
- `프로젝트`: 다른 프로젝트의 대상과 종속성을 선언합니다.
- `프레임워크`: 바이너리 프레임워크에 대한 종속성을 선언합니다.
- `라이브러리`: 바이너리 라이브러리와의 종속성을 선언합니다.
- `XC프레임워크`: 바이너리 XCFramework로 종속성을 선언합니다.
- `SDK`: 시스템 SDK와의 종속성을 선언합니다.
- `XCTest`: XCTest와의 종속성을 선언합니다.

> [참고] 종속성 조건 모든 종속성 유형은 플랫폼에 따라 종속성을 조건부로 연결하는 `조건` 옵션을 허용합니다. 기본적으로 이 옵션은 대상이
> 지원하는 모든 플랫폼에 대한 종속성을 연결합니다.

## 외부 종속성 {#external-dependencies}

또한 프로젝트에서 외부 종속성을 선언할 수 있습니다.

### 스위프트 패키지 {#swift-packages}

Swift 패키지는 프로젝트에서 종속성을 선언하는 데 권장되는 방법입니다. Xcode의 기본 통합 메커니즘을 사용하거나 Tuist의
XcodeProj 기반 통합을 사용하여 통합할 수 있습니다.

#### 튜이스트의 XcodeProj 기반 통합 {#tuists-xcodeprojbased-integration}

Xcode의 기본 통합은 가장 편리하지만 중대형 프로젝트에 필요한 유연성과 제어 기능이 부족합니다. 이를 극복하기 위해 Tuist는
XcodeProj의 타깃을 사용하여 프로젝트에 Swift 패키지를 통합할 수 있는 XcodeProj 기반 통합을 제공합니다. 덕분에 통합을 더
잘 제어할 수 있을 뿐만 아니라
<LocalizedLink href="/guides/features/cache">캐싱</LocalizedLink> 및
<LocalizedLink href="/guides/features/test/selective-testing">선택적 테스트
실행</LocalizedLink>과 같은 워크플로우와 호환되도록 만들 수 있습니다.

XcodeProj의 통합은 새로운 Swift 패키지 기능을 지원하거나 더 많은 패키지 구성을 처리하는 데 더 많은 시간이 걸릴 가능성이
높습니다. 그러나 Swift 패키지와 XcodeProj 대상 간의 매핑 로직은 오픈 소스이며 커뮤니티에서 기여할 수 있습니다. 이는 비공개
소스이며 Apple에서 유지 관리하는 Xcode의 기본 통합과는 상반됩니다.

외부 종속성을 추가하려면 `Tuist/` 또는 프로젝트의 루트에서 `Package.swift` 를 만들어야 합니다.

::: 코드 그룹
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

> [!TIP] 패키지 설정 컴파일러 지시어로 래핑된 `PackageSettings` 인스턴스를 사용하면 패키지가 통합되는 방식을 구성할 수
> 있습니다. 예를 들어 위 예제에서는 패키지에 사용되는 기본 제품 유형을 재정의하는 데 사용됩니다. 기본적으로 이 옵션은 필요하지 않습니다.

`Package.swift` 파일은 외부 종속성을 선언하는 인터페이스일 뿐 다른 것은 없습니다. 그렇기 때문에 패키지에서 대상이나 제품을
정의하지 않습니다. 종속성을 정의한 후에는 다음 명령을 실행하여 종속성을 해결하고 `Tuist/Dependencies` 디렉터리로 가져올 수
있습니다:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

이미 눈치채셨겠지만, 저희는 종속성 해결이 자체 명령인 [CocoaPods](https://cocoapods.org)'와 유사한 접근 방식을
취하고 있습니다. 이를 통해 사용자는 종속성 해결 및 업데이트 시기를 제어할 수 있으며, 프로젝트에서 Xcode를 열고 컴파일할 준비를 할 수
있습니다. 이 부분은 프로젝트가 성장함에 따라 Apple과 Swift 패키지 관리자의 통합이 제공하는 개발자 경험이 시간이 지남에 따라 저하되는
부분이라고 생각합니다.

그런 다음 프로젝트 대상에서 `TargetDependency.external` 종속성 유형을 사용하여 해당 종속성을 참조할 수 있습니다:

::: 코드 그룹
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
:::

> [참고] 외부 패키지에 대해 생성된 스키마 없음 **스키마** 는 스키마 목록을 깔끔하게 유지하기 위해 Swift 패키지 프로젝트에 대해
> 자동으로 생성되지 않습니다. Xcode의 UI를 통해 생성할 수 있습니다.

#### Xcode의 기본 통합 {#xcodes-default-integration}

Xcode의 기본 통합 메커니즘을 사용하려면 프로젝트를 인스턴스화할 때 `패키지의` 목록을 전달하면 됩니다:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

그런 다음 대상에서 참조하세요:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Swift 매크로 및 빌드 도구 플러그인의 경우 각각 `.macro` 및 `.plugin` 형식을 사용해야 합니다.

> [!경고] SPM 빌드 도구 플러그인 프로젝트 종속성에 대해 Tuist의 [XcodeProj 기반
> 통합](#tuist-s-xcodeproj-based-integration)을 사용하는 경우에도 [Xcode의 기본
> 통합](#xcode-s-default-integration) 메커니즘을 사용하여 SPM 빌드 도구 플러그인을 선언해야 합니다.

SPM 빌드 도구 플러그인의 실제 적용 사례는 Xcode의 "빌드 도구 플러그인 실행" 빌드 단계에서 코드 린팅을 수행하는 것입니다. 패키지
매니페스트에서는 다음과 같이 정의됩니다:

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

빌드 툴 플러그인을 그대로 유지한 채 Xcode 프로젝트를 생성하려면 프로젝트 매니페스트의 `패키지의` 배열에 패키지를 선언한 다음, 대상의
종속성에 `.plugin` 형식의 패키지를 포함시켜야 합니다.

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

### 카르타고 {#카르타고}

Carthage](https://github.com/carthage/carthage)는 `frameworks` 또는 `xcframeworks`
를 출력하므로 `carthage update` 를 실행하여 `Carthage/Build` 디렉터리에 종속성을 출력한 다음 `.framework`
또는 `.xcframework` 대상 종속성 유형을 사용하여 대상에 종속성을 선언할 수 있습니다. 이를 프로젝트를 생성하기 전에 실행할 수 있는
스크립트로 래핑할 수 있습니다.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!경고] 빌드 및 테스트 `tuist build` 및 `tuist test` 를 통해 프로젝트를 빌드하고 테스트하는 경우 마찬가지로
> `tuist build` 또는 `tuist test` 를 실행하기 전에 `carthage update` 명령을 실행하여 Carthage가
> 해결한 종속성이 존재하는지 확인해야 합니다.

### 코코아팟 {#코코아팟}

[CocoaPods](https://cocoapods.org)은 Xcode 프로젝트가 종속성을 통합할 것으로 예상합니다. Tuist를 사용하여
프로젝트를 생성한 다음 `pod install` 을 실행하여 프로젝트와 Pods 종속성이 포함된 작업 공간을 생성하여 종속성을 통합할 수
있습니다. 프로젝트를 생성하기 전에 실행할 수 있는 스크립트로 이 작업을 래핑할 수 있습니다.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!경고] 코코아팟 종속성은 프로젝트 생성 직후에 `xcodebuild` 를 실행하는 `build` 또는 `test` 와 같은 워크플로우와
> 호환되지 않습니다. 또한 핑거프린팅 로직이 Pods 종속성을 고려하지 않기 때문에 바이너리 캐싱 및 선택적 테스트와도 호환되지 않습니다.

## 정적 또는 동적 {#정적-또는-동적}

프레임워크와 라이브러리는 정적 또는 동적으로 연결할 수 있으며, **앱 크기 및 부팅 시간** 과 같은 측면에 중대한 영향을 미치는 선택입니다.
그 중요성에도 불구하고 이 결정은 많은 고려 없이 내려지는 경우가 많습니다.

**일반적인 경험 법칙(** )은 빠른 부팅 시간을 달성하기 위해 릴리스 빌드에서 가능한 한 많은 것을 정적으로 링크하고, 빠른 반복 시간을
달성하기 위해 디버그 빌드에서 가능한 한 많은 것을 동적으로 링크하는 것을 원한다는 것입니다.

프로젝트 그래프에서 정적 링크와 동적 링크 사이를 변경할 때의 문제는 변경 사항이 전체 그래프에 연쇄적으로 영향을 미치기 때문에(예:
라이브러리에 리소스를 포함할 수 없고, 정적 프레임워크는 임베드할 필요가 없음) Xcode에서 간단하지 않다는 것입니다. Apple은 정적
링크와 동적 링크 사이의 자동 결정 또는 [병합 가능한
라이브러리](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)와
같은 컴파일 시간 솔루션으로 이 문제를 해결하려고 시도했습니다. 그러나 이는 컴파일 그래프에 새로운 동적 변수를 추가하여 비결정성의 새로운
소스를 추가하고, 컴파일 그래프에 의존하는 Swift 미리보기와 같은 일부 기능을 불안정하게 만들 수 있습니다.

다행히도 Tuist는 정적과 동적 간의 변경과 관련된 복잡성을 개념적으로 압축하여 연결 유형 전반에 걸쳐 표준인
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">번들
접근자</LocalizedLink>를 합성합니다. 환경 변수</LocalizedLink>를 통한
<LocalizedLink href="/guides/features/projects/dynamic-configuration">동적 구성과
결합하면 호출 시 연결 유형을 전달하고 매니페스트의 값을 사용하여 타겟의 제품 유형을 설정할 수 있습니다.

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

튜이스트 <LocalizedLink href="/guides/features/projects/cost-of-convenience">은
비용</LocalizedLink> 때문에 암시적 설정을 통한 편의성을 기본값으로 제공하지 않는다는 점에 유의하세요. 즉, 결과 바이너리가
올바른지 확인하기 위해 사용자가 링크 유형과 [`-ObjC` 링커
플래그](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)와
같이 때때로 필요한 추가 빌드 설정을 설정하는 데 의존한다는 의미입니다. 따라서 올바른 결정을 내리는 데 도움이 되는 리소스를 문서 형태로
제공하는 것이 저희의 입장입니다.

> [!tip] 예제: 컴포저블 아키텍처 많은 프로젝트에서 통합하는 Swift 패키지는 [컴포저블
> 아키텍처](https://github.com/pointfreeco/swift-composable-architecture)입니다.
> 여기](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
> 및 [문제 해결 섹션](#troubleshooting)에 설명된 대로 패키지를 정적으로 링크할 때 `OTHER_LDFLAGS` 빌드 설정을
> `$(상속) -ObjC` 로 설정해야 하며, 이는 Tuist의 기본 링크 유형입니다. 또는 패키지를 동적으로 연결하려면 제품 유형을 재정의할
> 수 있습니다.

### 시나리오 {#시나리오}

링크를 정적 또는 동적으로만 설정하는 것이 가능하지 않거나 좋은 생각이 아닌 시나리오가 몇 가지 있습니다. 다음은 정적 링크와 동적 링크를
혼합해야 할 수 있는 시나리오의 전체 목록이 아닙니다:

- **확장 기능이 있는 앱:** 앱과 확장 프로그램은 코드를 공유해야 하므로 이러한 대상을 동적으로 만들어야 할 수 있습니다. 그렇지 않으면
  앱과 확장 프로그램 모두에 동일한 코드가 중복되어 바이너리 크기가 증가하게 됩니다.
- **미리 컴파일된 외부 종속성:** 정적이거나 동적인 사전 컴파일된 바이너리가 제공되는 경우가 있습니다. 정적 바이너리는 동적 프레임워크나
  라이브러리로 래핑하여 동적으로 연결할 수 있습니다.

그래프를 변경할 때 튜이스트는 그래프를 분석하여 '정적 부작용'을 감지하면 경고를 표시합니다. 이 경고는 동적 타깃을 통해 정적 타깃에
일시적으로 의존하는 타깃을 정적으로 연결할 때 발생할 수 있는 문제를 식별하는 데 도움을 주기 위한 것입니다. 이러한 부작용은 종종 바이너리
크기 증가 또는 최악의 경우 런타임 충돌로 나타납니다.

## 문제 해결 {#문제 해결}

### Objective-C 종속성 {#objectivec-dependencies}

Objective-C 종속성을 통합할 때 [Apple 기술 Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)에 설명된
대로 런타임 충돌을 방지하기 위해 소비 대상에 특정 플래그를 포함해야 할 수 있습니다.

빌드 시스템과 Tuist는 플래그가 필요한지 여부를 유추할 방법이 없고, 플래그에는 잠재적으로 바람직하지 않은 부작용이 있을 수 있기 때문에
Tuist는 이러한 플래그를 자동으로 적용하지 않으며, Swift 패키지 관리자는 `-ObjC` ` .unsafeFlag` 대부분의 패키지는
필요한 경우 기본 링크 설정의 일부로 포함할 수 없다고 간주하기 때문입니다.

오브젝티브-C 종속성(또는 내부 오브젝티브-C 대상)의 소비자는 필요한 경우 `-ObjC` 또는 `-force_load` 플래그를 적용하고,
소비 대상에 `OTHER_LDFLAGS` 를 설정해야 합니다.

### Firebase 및 기타 Google 라이브러리 {#firebase-other-google-libraries}

Google의 오픈 소스 라이브러리는 강력하지만 구축 방식에서 비표준 아키텍처와 기술을 사용하는 경우가 많기 때문에 Tuist 내에서 통합하기
어려울 수 있습니다.

다음은 Firebase와 Google의 다른 Apple 플랫폼 라이브러리를 통합하기 위해 따라야 할 몇 가지 팁입니다:

#### `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}에 `-ObjC` 가 추가되었는지 확인합니다.

Google의 많은 라이브러리는 Objective-C로 작성되었습니다. 따라서 이를 사용하는 모든 대상은 `OTHER_LDFLAGS` 빌드
설정에 `-ObjC` 태그를 포함해야 합니다. 이는 `.xcconfig` 파일에서 설정하거나 Tuist 매니페스트 내의 타겟 설정에서 수동으로
지정할 수 있습니다. 예시:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

자세한 내용은 위의 [Objective-C 종속성](#objective-c-dependencies) 섹션을 참조하세요.

#### `FBLPromises` 의 제품 유형을 동적 프레임워크로 설정 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

특정 Google 라이브러리는 `FBLPromises`, 또 다른 Google 라이브러리에 의존합니다. 다음과 같이 보이는
`FBLPromises` 를 언급하는 크래시가 발생할 수 있습니다:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` 파일에서 `FBLPromises` 의 제품 유형을 `.framework` 로 명시적으로 설정하면 문제가 해결됩니다:

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

### 전이적 정적 종속성 유출 `.swiftmodule` {#전이적-정적-종속성 유출-스위프트모듈}

동적 프레임워크 또는 라이브러리가 `import StaticSwiftModule` 을 통해 정적 프레임워크 또는 라이브러리에 의존하는 경우,
해당 심볼이 동적 프레임워크 또는 라이브러리의 `.swiftmodule` 에 포함되어
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">컴파일이
실패</LocalizedLink>할 수 있습니다. 이를 방지하려면
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink>를 사용하여 정적 종속성을 임포트해야 합니다:

```swift
internal import StaticModule
```

> [참고] 가져오기에 대한 액세스 수준은 Swift 6에 포함되었습니다. 이전 버전의 Swift를 사용하는 경우
> <LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>를
> 대신 사용해야 합니다:

```swift
@_implementationOnly import StaticModule
```
