---
{
  "title": "모듈형 아키텍처(TMA)",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "모듈형 아키텍처(TMA)와 이를 활용해 프로젝트를 구조화하는 방법을 알아보세요."
}
---
# 모듈형 아키텍처(TMA) {#the-modular-architecture-tma}

TMA는 확장성을 가능하게 하고 빌드 및 테스트 주기를 최적화하며 팀 내 모범 사례를 보장하기 위해 애플리케이션을 구조화하는 아키텍처 접근 방식입니다. 핵심 아이디어는 명확하고 간결한 API로 상호 연결된 독립적인 기능을 구축하여 앱을 만드는 것입니다.

이 가이드라인은 아키텍처의 원칙을 소개하여 다양한 레이어에서 애플리케이션 기능을 식별하고 구성하는 데 도움을 줍니다. 또한 이 아키텍처를 사용하기로 결정했을 때 유용한 팁, 도구 및 조언도 제공합니다.

> [!NOTE]
> **µ기능**
>
> 이 아키텍처는 이전에 µFeatures로 알려져 있었습니다. 목적과 그 배경에 있는 원칙을 더 잘 반영하기 위해 모듈형 아키텍처(TMA)로 이름을 변경했습니다.


## 핵심 원칙 {#core-principle}

개발자는 UI 미리보기, 코드 완성 및 디버깅과 같은 Xcode 기능이 안정적으로 작동하도록 보장하면서 메인 앱과 독립적으로 자신의 기능을 빠르게 **빌드, 테스트 및 시도**할 수 있어야 합니다.

## 모듈이란 무엇인가 {#what-is-a-module}

모듈은 애플리케이션 기능을 나타내며 다음 다섯 가지 타겟(Xcode 타겟을 의미함)의 조합입니다:

- **소스:** 기능 소스 코드(Swift, Objective-C, C++, JavaScript...)와 리소스(이미지, 폰트, 스토리보드, xib)를 포함합니다.
- **인터페이스:** 기능의 공개 인터페이스와 모델을 포함하는 동반 타겟입니다.
- **테스트:** 기능 단위 테스트 및 통합 테스트를 포함합니다.
- **테스팅:** 테스트와 예제 앱에서 사용할 수 있는 테스트 데이터를 제공합니다. 또한 나중에 보게 될 다른 기능에서 사용할 수 있는 모듈 클래스와 프로토콜에 대한 목(mock)을 제공합니다.
- **예제:** 개발자가 특정 조건(다른 언어, 화면 크기, 설정)에서 기능을 시험해 볼 수 있도록 하는 예제 앱을 포함합니다.

타겟에 대한 명명 규칙을 따르는 것을 권장하며, Tuist의 DSL 덕분에 프로젝트에서 이를 강제할 수 있습니다.

| 타겟 | 종속성 | 내용 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | 소스 코드 및 리소스 |
| `FeatureInterface` | - | 공개 인터페이스 및 모델 |
| `FeatureTests` | `Feature`, `FeatureTesting` | 단위 및 통합 테스트 |
| `FeatureTesting` | `FeatureInterface` | 테스트 데이터 및 목(mock) |
| `FeatureExample` | `FeatureTesting`, `Feature` | 예제 앱 |

> [!TIP]
> **UI 미리보기**
>
> `Feature`는 UI 미리보기를 허용하기 위해 `FeatureTesting`를 개발 에셋으로 사용할 수 있습니다.


> [!WARNING]
> **테스트 타겟 대신 컴파일러 지시문 사용**
>
> 대안으로, `Debug`용으로 컴파일할 때 `Feature` 또는 `FeatureInterface` 타겟에 테스트 데이터와 목(mock)을 포함하기 위해 컴파일러 지시문을 사용할 수 있습니다. 그래프가 단순해지지만, 앱 실행에는 필요하지 않은 코드를 컴파일하게 됩니다.


## 왜 모듈인가 {#why-a-module}

### 명확하고 간결한 API {#clear-and-concise-apis}

모든 앱 소스 코드가 동일한 타겟에 존재하면 코드에서 암시적 종속성을 쉽게 구축하게 되고 잘 알려진 스파게티 코드로 끝나기 쉽습니다. 모든 것이 강하게 결합되어 있고 상태가 때로는 예측 불가능하며 새로운 변경 사항을 도입하는 것은 악몽이 됩니다. 독립적인 타겟에서 기능을 정의할 때 기능 구현의 일부로 공개 API를 설계해야 합니다. 무엇을 공개해야 할지, 기능을 어떻게 소비해야 할지, 무엇을 비공개로 유지해야 할지 결정해야 합니다. 기능 클라이언트가 기능을 사용하는 방식에 대해 더 많은 제어권을 가질 수 있으며 안전한 API를 설계함으로써 모범 사례를 강제할 수 있습니다.

### 작은 모듈 {#small-modules}

[분할 정복](https://en.wikipedia.org/wiki/Divide_and_conquer). 작은 모듈로 작업하면 더 집중할 수 있고 기능을 격리된 상태에서 테스트하고 시도할 수 있습니다. 또한 기능이 작동하는 데 필요한 구성 요소만 컴파일하는 선택적 컴파일을 수행하므로 개발 주기가 훨씬 빠릅니다. 전체 앱의 컴파일은 작업을 마무리하고 기능을 앱에 통합해야 할 때만 필요합니다.

### 재사용성 {#reusability}

프레임워크나 라이브러리를 사용하여 앱과 확장 프로그램과 같은 다른 제품 간에 코드를 재사용하는 것이 권장됩니다. 모듈을 구축하면 재사용이 매우 간단해집니다. 기존 모듈을 조합하고 _(필요한 경우)_ 플랫폼별 UI 레이어를 추가함으로써 iMessage 확장 프로그램, Today Extension 또는 watchOS 애플리케이션을 구축할 수 있습니다.

## 종속성 {#dependencies}

모듈이 다른 모듈에 종속될 때 해당 인터페이스 타겟에 대한 종속성을 선언합니다. 이는 두 가지 이점이 있습니다. 한 모듈의 구현이 다른 모듈의 구현과 결합되는 것을 방지하고, 기능의 구현과 직접 및 간접 종속성의 인터페이스만 컴파일하면 되므로 완전 빌드(clean build) 속도가 빨라집니다. 이 접근 방식은 SwiftRock의 [인터페이스 모듈을 사용하여 iOS 빌드 시간 단축](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets) 아이디어에서 영감을 받았습니다.

인터페이스에 의존하려면 앱이 런타임에 구현 그래프를 구축하고 이를 필요한 모듈에 종속성 주입(dependency-inject)해야 합니다. TMA는 이를 수행하는 방법에 대해 특정 방식을 강요하지 않지만, 빌드 시간 간접 참조를 추가하거나 이 목적으로 설계되지 않은 플랫폼 API를 사용하지 않는 종속성 주입 솔루션이나 패턴을 사용하는 것을 권장합니다.

## 제품 유형 {#product-types}

모듈을 빌드할 때 타겟에 대해 **라이브러리 및 프레임워크** 중 하나와 **정적 및 동적 링크** 중 하나를 선택할 수 있습니다. Tuist 없이는 종속성 그래프를 수동으로 구성해야 하므로 이 결정을 내리는 것이 조금 더 복잡합니다. 그러나 Tuist Projects 덕분에 이는 더 이상 문제가 되지 않습니다.

개발 중에는 <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">번들 액세서</.localized_link>를 사용하여 동적 라이브러리나 프레임워크를 사용하는 것을 권장합니다. 이를 통해 번들 접근 로직을 타겟의 라이브러리 또는 프레임워크 특성으로부터 분리할 수 있습니다. 이는 빠른 컴파일 시간을 확보하고 [SwiftUI 미리보기](https://developer.apple.com/documentation/swiftui/previews-in-xcode)가 안정적으로 작동하도록 보장하는 데 핵심적입니다. 그리고 앱이 빠르게 부팅되도록 릴리스 빌드에는 정적 라이브러리나 프레임워크를 사용합니다. 생성 시점에 제품 유형을 변경하기 위해 <.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">동적 구성</.localized_link>을 활용할 수 있습니다:

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


> [!WARNING]
> **병합 가능한 라이브러리**
>
> Apple은 정적 및 동적 라이브러리 간 전환의 번거로움을 완화하기 위해 [병합 가능한 라이브러리](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)를 도입했습니다. 그러나 이는 빌드 시간 비결정성을 초래하여 빌드를 재현 불가능하게 만들고 최적화를 어렵게 하므로 사용을 권장하지 않습니다.


## 코드 {#code}

TMA는 모듈의 코드 아키텍처와 패턴에 대해 특정 방식을 강요하지 않습니다. 다만, 경험을 바탕으로 몇 가지 팁을 공유하고자 합니다:

- **컴파일러를 활용하는 것은 좋습니다.** 컴파일러를 지나치게 의존하면 생산성이 떨어지고 미리보기와 같은 일부 Xcode 기능이 불안정하게 작동할 수 있습니다. 컴파일러를 사용하여 모범 사례를 강제하고 오류를 조기에 발견하는 것을 권장하지만, 코드를 읽고 유지보수하기 어렵게 만들 정도까지는 피해야 합니다.
- **Swift 매크로는 신중하게 사용하세요.** 매우 강력할 수 있지만 코드를 읽고 유지보수하기 어렵게 만들 수도 있습니다.
- **플랫폼과 언어를 수용하고 추상화하지 마세요.** 복잡한 추상화 계층을 고안하려는 시도는 오히려 역효과를 낼 수 있습니다. 플랫폼과 언어는 추가적인 추상화 계층 없이도 훌륭한 앱을 구축할 만큼 충분히 강력합니다. 기능을 구축할 때 좋은 프로그래밍 및 디자인 패턴을 참고 자료로 활용하세요.


## 리소스 {#resources}

- [µFeatures 구축하기](https://speakerdeck.com/pepibumur/building-ufeatures)
- [프레임워크 중심 프로그래밍](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [프레임워크와 Swift로의 여정](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [iOS 개발 속도 향상을 위한 프레임워크 활용 - 파트 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [라이브러리 중심 프로그래밍](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [현대적 프레임워크 구축하기](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 파일 비공식 가이드](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [정적 및 동적 라이브러리](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
