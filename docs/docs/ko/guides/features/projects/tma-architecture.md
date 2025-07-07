---
title: The Modular Architecture (TMA)
titleTemplate: :title · Projects · Features · Guides · Tuist
description: The Modular Architecture (TMA) 에 대해 배우고, 이를 사용하여 프로젝트를 구조화 하는 방법을 배워봅니다.
---

# The Modular Architecture (TMA) {#the-modular-architecture-tma}

TMA는 Apple OS 애플리케이션을 구조화 하는 아키텍처 접근 방식이고, 확장성을 가지며, 빌드와 테스트 주기를 최적화 하고, 팀 내에 좋은 개발 방식을 보장합니다. 이것의 핵심은 독립적인 기능을 만들고 명확하고 간결한 API를 통해 서로 연결하여 애플리케이션을 만드는 것입니다.

이 가이드라인은 아키텍처의 원칙을 소개하며, 다른 계층의 애플리케이션 기능을 식별하고 연결하는데 도움을 줍니다. 이 아키텍처를 사용하기로 결정한다면, 도움이 되는 팁, 툴, 그리고 충고도 소개합니다.

> [!INFO] µFEATURES\
> 이 아키텍처는 이전에 µFeatures로 알려진 아키텍처 입니다. 우리는 이 아키텍처의 목적과 원칙이 더 잘 반영되도록 The Modular Architecture (TMA) 로 이름을 변경했습니다.

## 주요 원칙 {#core-principle}

개발자는 메인 앱과 독립적으로 기능을 빠르게 **빌드, 테스트, 그리고 실행** 할 수 있어야 하고, Xcode의 UI 프리뷰, 코드 자동 완성, 그리고 디버깅 기능이 잘 동작해야 합니다.

## 모듈이란 무엇인가 {#what-is-a-module}

모듈은 애플리케이션 기능이며, 다음의 다섯가지 타겟 (여기서 타겟은 Xcode 타겟을 의미) 의 조합입니다:

- **Source:** 기능의 소스 코드 (Swift, Objective-C, C++, JavaScript...) 와 리소스 (이미지, 폰트, 스토리보드, xib) 를 포함합니다.
- **Interface:** 기능의 공개 인터페이스와 모델을 포함하는 보조 타겟입니다.
- **Tests:** 기능의 단위 테스트와 통합 테스트를 포함합니다.
- **Testing:** 테스트와 예제 앱에서 사용될 수 있는 테스트 데이터를 제공합니다. 또한, 나중에 볼 수 있듯이 다른 기능에서 사용할 수 있는 모듈 클래스와 프로토콜에 대한 모의 객체 (Mock) 를 제공합니다.
- **Example:** 개발자가 특정 조건 (다른 언어, 다른 화면 크기, 다른 설정) 에서 기능을 확인하는데 사용할 수 있는 예제 앱을 포함합니다.

타겟에 네이밍 규칙을 따를 것을 권장하며, 이는 Tuist의 DSL 덕분에 프로젝트에 강제로 적용할 수 있습니다.

| Target             | Dependencies                | Content        |
| ------------------ | --------------------------- | -------------- |
| `Feature`          | `FeatureInterface`          | 소스 코드와 리소스     |
| `FeatureInterface` | -                           | 공개 인터페이스와 모델   |
| `FeatureTests`     | `Feature`, `FeatureTesting` | 단위 테스트와 통합 테스트 |
| `FeatureTesting`   | `FeatureInterface`          | 테스트 데이터와 모의 객체 |
| `FeatureExample`   | `FeatureTesting`, `Feature` | 예제 앱           |

> [!TIP] UI 프리뷰\
> `Feature`는 UI 프리뷰를 사용하기 위해 Development Asset으로 `FeatureTesting`을 사용할 수 있습니다.

> [!IMPORTANT] 테스트 타겟 대신 컴파일러 지시문\
> 또한, `Debug`로 컴파일할 때 `Feature`나 `FeatureInterface`에 테스트 데이터와 모의 객체를 포함하기 위해 컴파일러 지시문을 사용할 수 있습니다. 그래프를 단순화할 수 있지만, 결국 앱을 실행하는데 필요하지 않은 코드를 컴파일하게 될 수 있습니다.

## 왜 모듈인가 {#why-a-module}

### 명확하고 간결한 API {#clear-and-concise-apis}

모든 앱 소스 코드가 같은 타겟에 있으면 코드에서 암시적 의존성이 쉽게 생기고 결국 잘 알려진 스파게티 코드가 될 수 있습니다. 모든 것이 강하게 결합되어 있고, 상태는 예측하기 힘들어지고, 새로운 변경 사항을 도입하기 힘들어 집니다. 독립적인 타겟에 기능을 정의할 때 기능 구현의 일환으로 공개 API를 설계해야 합니다. 우리는 무엇을 공개할지, 기능이 어떻게 사용되어야 할지, 무엇을 비공개로 남겨야 할지 결정해야 합니다. 우리는 기능 클라이언트가 기능을 어떻게 사용할지에 대해 더 많은 제어를 할 수 있고, 안전한 API 설계로 좋은 개발 방식을 강제할 수 있습니다.

### 작은 모듈 {#small-modules}

[분할 정복 (Divide and conquer)](https://en.wikipedia.org/wiki/Divide_and_conquer). 작은 모듈로 작업하면 더 집중할 수 있고 기능을 독립적으로 테스트하고 확인할 수 있습니다. 게다가 개발 주기는 훨씬 더 빨라지는데, 이는 기능을 동작시키기 위해 필요한 컴포넌트만 컴파일하는 선택적 컴파일 덕분입니다. 앱 전체의 컴파일은 작업의 마지막에만 필요하며 이때 앱에 기능을 통합해야 합니다.

### 재사용성 {#reusability}

코드를 앱과 확장과 같은 다른 결과물에 재사용하는 것은 프레임워크나 라이브러리를 사용하도록 권장합니다. 모듈을 구축하면 코드 재사용이 매우 간단해 집니다. 기존 모듈을 결합하고 _(필요할 때)_ 플랫폼 별 UI 계층을 추가하여 iMessage 확장, Today 확장, 또는 watchOS 애플리케이션을 만들 수 있습니다.

## 의존성 {#dependencies}

모듈이 다른 모듈에 의존할 경우, 해당 모듈은 의존할 모듈의 인터페이스 타겟에 대한 의존성을 선언합니다. 이러면 두 가지 장점이 있습니다. 하나의 모듈 구현이 다른 모듈 구현과 결합되는 것을 방지하고, 기능의 구현만 컴파일하고 직접적인 의존성과 전이적 의존성에 대한 인터페이스만 컴파일하면 되므로 클린 빌드 속도가 빨라집니다. 이 접근 방식은 SwiftRock의 [인터페이스 모듈을 사용하여 iOS 빌드 시간 단축](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)에서 영감을 얻었습니다.

인터페이스에 의존하는 것은 앱이 실행 시간에 구현의 그래프를 구성하고, 필요한 모듈에 해당 구현을 의존성 주입해야 합니다. TMA는 이를 어떻게 구현할지 강제하지 않지만, 빌드 시간에 불필요한 간접 참조를 추가하거나 이 목적을 위해 설계되지 않은 플랫폼 API를 사용하지 않는 의존성 주입 솔루션이나 패턴을 권장합니다.

## 결과물 타입 {#product-types}

모듈을 구축할 때, 타겟에 대한 **라이브러리와 프레임워크** 및 **정적과 동적 링킹** 중 선택할 수 있습니다. Tuist가 없다면 의존성 그래프를 수동으로 구성해야 하므로 이 결정을 내리는데 더 복잡합니다. 하지만 Tuist 프로젝트 덕분에 이건 아무런 문제가 되지 않습니다.

타겟의 라이브러리나 프레임워크 특성과 번들 접근 로직을 분리하기 위해 개발 중에는 <LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">번들 접근자</LocalizedLink>를 사용하여 동적 라이브러리나 동적 프레임워크를 사용하길 권장합니다. 이것은 빠른 컴파일 시간과 [SwiftUI 프리뷰](https://developer.apple.com/documentation/swiftui/previews-in-xcode)가 잘 동작하기 위해 중요한 포인트입니다. 그리고 릴리즈 빌드에서 앱이 더 빠르게 실행되기 위해 정적 라이브러리나 정적 프레임워크를 사용하는 것이 좋습니다. <0>동적 구성</0>을 활용하여 생성 시점에 결과물 타입을 변경할 수 있습니다:

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```

> [!IMPORTANT] MERGEABLE LIBRARIES\
> Apple은 [mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)를 도입하여 정적 라이브러리와 동적 라이브러리 간 변환의 번거로움을 줄이려고 했습니다. 하지만 이것은 빌드 시 항상 동일한 결과를 가져오지 않고 최적화가 어려워 지기 때문에 권장하지 않습니다.

## 코드 {#code}

TMA는 모듈의 코드 아키텍처와 패턴에 대해 강요하지 않습니다. 하지만, 경험을 토대로 몇가지 팁을 공유하려고 합니다:

- **컴파일러를 활용하는 것은 훌륭합니다.** 그러나 컴파일러를 과도하게 사용하면 비생산적이며 프리뷰와 같은 Xcode의 기능이 원할하게 동작하지 않을 수 있습니다. 우리는 컴파일러를 사용하여 좋은 코드작성 관행과 조기에 오류를 찾도록 권장하지만, 코드를 읽기 어렵고 유지 보수 하기 어렵도록 사용하는 것은 권장하지 않습니다.
- **Swift Macros는 신중하게 사용해야 합니다.** 이것은 매우 강력하지만 코드를 읽기 어렵고 유지 보수 하기 어렵게 만들 수도 있습니다.
- **플랫폼과 언어를 받아들이고, 추상화 하지 말아야 합니다.** 복잡한 추상화 계층을 만들면 오히려 비효율적일 수 있습니다. 플랫폼과 언어는 추가적인 추상화 계층없이도 훌륭한 앱을 만들기에 충분합니다. 좋은 프로그래밍과 좋은 설계 패턴을 참조하여 기능을 구축합니다.

## 리소스 {#resources}

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Leveraging frameworks to speed up our development on iOS - Part 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library Oriented Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [The Unofficial Guide to xcconfig files](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Static and Dynamic Libraries](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
