---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# 모듈형 아키텍처(TMA) {#the-modular-architecture-tma}

TMA는 확장성을 지원하고 빌드 및 테스트 주기를 최적화하며 팀의 모범 사례를 보장하기 위해 Apple OS 애플리케이션을 구조화하는 아키텍처적
접근 방식입니다. 핵심 아이디어는 명확하고 간결한 API를 사용하여 상호 연결된 독립적인 기능을 구축하여 앱을 빌드하는 것입니다.

이 가이드라인에서는 아키텍처의 원칙을 소개하여 애플리케이션 기능을 여러 계층으로 식별하고 구성하는 데 도움을 줍니다. 또한 이 아키텍처를
사용하기로 결정한 경우 유용한 팁, 도구 및 조언도 소개합니다.

::: info µFEATURES
<!-- -->
이 아키텍처는 이전에는 µFeatures로 알려졌습니다. 그 목적과 원칙을 더 잘 반영하기 위해 모듈형 아키텍처(TMA)로 이름을 변경했습니다.
<!-- -->
:::

## 핵심 원칙 {#core-principle}

**개발자는 메인 앱과 독립적으로 빠르게 기능을 빌드, 테스트 및** 사용해 볼 수 있어야 하며, UI 미리보기, 코드 완성 및 디버깅과 같은
Xcode 기능이 안정적으로 작동하도록 보장해야 합니다.

## 모듈이란 {#what-is-a-module}이란 무엇인가요?

모듈은 애플리케이션 기능을 나타내며 다음 다섯 가지 타깃의 조합입니다(여기서 타깃은 Xcode 타깃을 의미함):

- **소스:** 기능 소스 코드(Swift, Objective-C, C++, JavaScript 등)와 해당 리소스(이미지, 폰트,
  스토리보드, xib)가 포함되어 있습니다.
- **인터페이스:** 기능의 공용 인터페이스와 모델을 포함하는 컴패니언 타겟입니다.
- **테스트:** 기능 단위 및 통합 테스트가 포함되어 있습니다.
- **테스트:** 테스트 및 예제 앱에서 사용할 수 있는 테스트 데이터를 제공합니다. 또한 나중에 살펴보겠지만 다른 기능에서 사용할 수 있는
  모듈 클래스 및 프로토콜에 대한 모의도 제공합니다.
- **예제:** 예: 개발자가 특정 조건(다양한 언어, 화면 크기, 설정)에서 기능을 사용해 볼 수 있는 예제 앱이 포함되어 있습니다.

대상에 대한 명명 규칙을 따르는 것이 좋으며, 이는 Tuist의 DSL을 통해 프로젝트에 적용할 수 있습니다.

| Target    | 의존성            | 콘텐츠           |
| --------- | -------------- | ------------- |
| `기능`      | `기능인터페이스`      | 소스 코드 및 리소스   |
| `기능인터페이스` | -              | 공용 인터페이스 및 모델 |
| `기능 테스트`  | `기능`, `기능 테스트` | 단위 및 통합 테스트   |
| `기능 테스트`  | `기능인터페이스`      | 데이터 및 모의 테스트  |
| `기능예시`    | `기능 테스트`, `기능` | 앱 예시          |

::: 팁 UI 미리보기
<!-- -->
`Feature` 는 `FeatureTesting` 을 개발 에셋으로 사용하여 UI 미리 보기를 허용할 수 있습니다.
<!-- -->
:::

::: 경고 컴파일러가 테스트 대상 대신 지시합니다.
<!-- -->
또는 컴파일러 지시어를 사용하여 `디버그` 를 위해 컴파일할 때 `Feature` 또는 `FeatureInterface` 타깃에 테스트 데이터와
모의 코드를 포함할 수 있습니다. 그래프를 단순화할 수 있지만 앱 실행에 필요하지 않은 코드를 컴파일하게 됩니다.
<!-- -->
:::

## 모듈 {#why-a-module}이 필요한 이유

### 명확하고 간결한 API {#clear-and-concise-apis}

모든 앱 소스 코드가 동일한 대상에 있으면 코드에 암시적 종속성을 구축하기가 매우 쉬우며, 결국 잘 알려진 스파게티 코드가 됩니다. 모든 것이
강력하게 결합되어 있고 상태를 예측할 수 없으며 새로운 변경 사항을 도입하는 것은 악몽이 됩니다. 독립적인 타깃에서 기능을 정의할 때는 기능
구현의 일부로 공용 API를 설계해야 합니다. 무엇이 공개되어야 하는지, 기능이 어떻게 소비되어야 하는지, 무엇이 비공개로 유지되어야 하는지
결정해야 합니다. 기능 클라이언트가 기능을 사용하는 방식을 더 잘 제어할 수 있고 안전한 API를 설계하여 모범 사례를 시행할 수 있습니다.

### 소형 모듈 {#small-modules}

[분할 및 정복](https://en.wikipedia.org/wiki/Divide_and_conquer). 작은 모듈로 작업하면 더 집중해서
기능을 개별적으로 테스트하고 시도할 수 있습니다. 또한 기능을 작동시키는 데 필요한 컴포넌트만 컴파일하는 선택적 컴파일이 가능하기 때문에 개발
주기가 훨씬 빨라집니다. 전체 앱의 컴파일은 기능을 앱에 통합해야 하는 작업의 맨 마지막에만 필요합니다.

### 재사용 가능성 {#reusability}

프레임워크나 라이브러리를 사용하여 앱과 확장 프로그램과 같은 다른 제품에서 코드를 재사용하는 것이 좋습니다. 모듈을 구축하여 재사용하는 것은
매우 간단합니다. 기존 모듈을 결합하고 _(필요한 경우)_ 플랫폼별 UI 레이어를 추가하기만 하면 iMessage 확장 프로그램, Today
확장 프로그램 또는 watchOS 애플리케이션을 구축할 수 있습니다.

## 의존성 {#dependencies}

모듈이 다른 모듈에 종속되면 해당 인터페이스 대상에 대한 종속성을 선언합니다. 이 방법의 장점은 두 가지입니다. 모듈의 구현이 다른 모듈의
구현에 결합되는 것을 방지하고, 직접 및 전이 종속성의 인터페이스와 기능의 구현만 컴파일하면 되므로 깔끔한 빌드 속도를 높일 수 있습니다. 이
접근 방식은 SwiftRock의 [인터페이스 모듈을 사용하여 iOS 빌드 시간
단축](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)이라는
아이디어에서 영감을 얻었습니다.

인터페이스에 따라 앱은 런타임에 구현 그래프를 작성하고 이를 필요로 하는 모듈에 종속성 주입을 해야 합니다. TMA는 이를 수행하는 방법에 대해
의견을 제시하지 않지만, 빌드 타임 간접화를 추가하거나 이러한 목적으로 설계되지 않은 플랫폼 API를 사용하지 않는 의존성 주입 솔루션이나 패턴
또는 솔루션을 사용할 것을 권장합니다.

## 제품 유형 {#product-types}

모듈을 빌드할 때 **라이브러리 및 프레임워크**, **정적 및 동적 링크** 중에서 대상을 선택할 수 있습니다. Tuist가 없었다면 종속성
그래프를 수동으로 구성해야 하기 때문에 이러한 결정을 내리는 것이 조금 더 복잡했습니다. 하지만 이제 Tuist 프로젝트 덕분에 더 이상 문제가
되지 않습니다.

개발 중에
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">번들 접근자</LocalizedLink>를 사용하여 동적 라이브러리 또는 프레임워크를 사용하면 번들 액세스 로직을 대상의 라이브러리 또는 프레임워크
특성에서 분리하는 것이 좋습니다. 이는 컴파일 시간을 단축하고 [SwiftUI
미리보기](https://developer.apple.com/documentation/swiftui/previews-in-xcode)가
안정적으로 작동하도록 하기 위한 핵심 요소입니다. 또한 릴리스 빌드를 위한 정적 라이브러리 또는 프레임워크는 앱이 빠르게 부팅되도록 합니다.
<LocalizedLink href="/guides/features/projects/dynamic-configuration">동적 구성</LocalizedLink>을 활용하여 생성 시점에 제품 유형을 변경할 수 있습니다:

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


::: 경고 병합 가능한 라이브러리
<!-- -->
Apple은 [병합 가능한
라이브러리](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)를
도입하여 정적 라이브러리와 동적 라이브러리 간 전환의 번거로움을 완화하려고 시도했습니다. 그러나 이는 빌드 시간 비결정성을 도입하여 빌드를
재현할 수 없고 최적화하기 어렵게 만들므로 사용하지 않는 것이 좋습니다.
<!-- -->
:::

## 코드 {#code}

TMA는 모듈의 코드 아키텍처와 패턴에 대해 의견을 제시하지 않습니다. 하지만 저희의 경험을 바탕으로 몇 가지 팁을 공유하고자 합니다:

- **컴파일러를 활용하는 것은 좋습니다.** 컴파일러를 과도하게 활용하면 생산성이 떨어지고 미리보기와 같은 일부 Xcode 기능이 불안정하게
  작동할 수 있습니다. 컴파일러는 모범 사례를 적용하고 오류를 조기에 발견하기 위해 사용하는 것이 좋지만, 코드를 읽고 유지 관리하기 어렵게
  만드는 정도까지는 사용하지 않는 것이 좋습니다.
- **Swift 매크로는 아껴서 사용하세요.** 매크로는 매우 강력할 수 있지만 코드를 읽고 유지 관리하기 어렵게 만들 수도 있습니다.
- **플랫폼과 언어를 추상화하지 말고 수용하세요.** 정교한 추상화 계층을 만들려고 하면 오히려 비생산적인 결과를 초래할 수 있습니다.
  플랫폼과 언어는 추가적인 추상화 계층 없이도 훌륭한 앱을 구축할 수 있을 만큼 강력합니다. 좋은 프로그래밍 및 디자인 패턴을 참조하여 기능을
  구축하세요.

## 리소스 {#resources}

- [건물 µ기능](https://speakerdeck.com/pepibumur/building-ufeatures)
- [프레임워크 지향
  프로그래밍](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [프레임워크와 스위프트로의
  여정](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [프레임워크를 활용하여 iOS에서 개발 속도 높이기 -
  1부](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [라이브러리 지향
  프로그래밍](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [최신 프레임워크 구축](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 파일에 대한 비공식
  가이드](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [정적 및 동적
  라이브러리](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
