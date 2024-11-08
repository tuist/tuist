---
title: The Modular Architecture (TMA)
titleTemplate: :title · Projects · Develop · Guides · Tuist
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

### Reusability {#reusability}

Reusing code across apps and other products like extensions is encouraged using frameworks or libraries. By building modules reusing them is pretty straightforward. We can build an iMessage extension, a Today Extension, or a watchOS application by just combining existing modules and adding _(when necessary)_ platform-specific UI layers.

## 의존성 {#dependencies}

When a module depends on another module, it declares a dependency against its interface target. The benefit of this is two-fold. It prevents the implementation of a module to be coupled to the implementation of another module, and it speeds up clean builds because they only have to compile the implementation of our feature, and the interfaces of direct and transitive dependencies. This approach is inspired by SwiftRock's idea of [Reducing iOS Build Times by using Interface Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Depending on interfaces requires apps to build the graph of implementations at runtime, and dependency-inject it into the modules that need it. Although TMA is non-opinionated about how to do this, we recommend using dependency-injection solutions or patterns or solutions that don't add built-time indirections or use platform APIs that were not designed for this purpose.

## Product types {#product-types}

When building a module, you can choose between **libraries and frameworks**, and **static and dynamic linking** for the targets. Without Tuist, making this decision is a bit more complex because you need to configure the dependency graph manually. However, thanks to Tuist Projects, this is no longer a problem.

We recommend using dynamic libraries or frameworks during development using <LocalizedLink href="/guides/develop/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink> to decouple the bundle-accessing logic from the library or framework nature of the target. This is key for fast compilation times and to ensure [SwiftUI Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) work reliably. And static libraries or frameworks for the release builds to ensure the app boots fast. You can leverage <LocalizedLink href="/guides/develop/projects/dynamic-configuration#configuration-through-environment-variables">dynamic configuration</LocalizedLink> to change the product type at generation-time:

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

> [!IMPORTANT] MERGEABLE LIBRARIES
> Apple attempted to alleviate the cumbersomeness of switching between static and dynamic libraries by introducing [mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). However, that introduces build-time non-determinism that makes your build non-reproducible and harder to optimize so we don't recommend using it.

## Code {#code}

TMA is non-opinionated about the code architecture and patterns for your modules. However, we'd like to share some tips based on our experience:

- **Leveraging the compiler is great.** Over-leveraging the compiler might end up being non-productive and cause some Xcode features like previews to work unreliably. We recommend using the compiler to enforce good practices and catch errors early, but not to the point that it makes the code harder to read and maintain.
- **Use Swift Macros sparingly.** They can be very powerful but can also make the code harder to read and maintain.
- **Embrace the platform and the language, don't abstract them.** Trying to come up with ellaborated abstraction layers might end up being counterproductive. The platform and the language are powerful enough to build great apps without the need for additional abstraction layers. Use good programming and design patterns as a reference to build your features.

## 리소스 {#resources}

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Leveraging frameworks to speed up our development on iOS - Part 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Library Oriented Programming](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [The Unofficial Guide to xcconfig files](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Static and Dynamic Libraries](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
