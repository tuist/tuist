---
title: The cost of convenience
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Xcode에서 편의성의 비용에 대해 알아보고 Tuist는 이 문제를 어떻게 예방하는지 배워봅니다.
---

# The cost of convenience {#the-cost-of-convenience}

**작은 프로젝트에서 대규모 프로젝트까지** 사용할 수 있는 코드 편집기를 설계하는 것은 어려운 작업입니다.
이 문제를 해결하기 위해 많은 툴은 솔루션을 계층화하고 확장성을 제공하는 방식으로 접근합니다. 최하위 계층은 매우 저수준이며 기본 빌드 시스템과 밀접하게 연결되어 있고, 최상위 계층은 사용하기 편리하지만 유연성이 떨어지는 고수준 추상화 입니다.
이렇게 함으로써, 간단한 것은 쉽게 만들고 그 외 모든 것을 가능하게 만듭니다.

그러나,
**[Apple](https://www.apple.com)은 Xcode에 다른 접근 방식을 취하기로 결정했습니다**.
그 이유는 명확하지 않지만, 대규모 프로젝트에 대해 최적화 하는 것이 목표가 아니었을 확률이 큽니다.
그들은 소규모 프로젝트에 대한 편리성에 과도하게 투자하고, 유연성은 거의 제공하지 않으며, 기본 빌드 시스템과 툴을 강하게 결합시켰습니다.
편리함을 제공하기 위해, Apple은 쉽게 대체할 수 있는 기본 설정을 제공하고, 대규모 프로젝트에서 문제를 일으키는 암시적인 빌드 타임 해석 동작을 추가했습니다.

## 명시성과 규모 {#explicitness-and-scale}

대규모 작업을 할 때, **명시성은 핵심입니다**.
명시성은 빌드 시스템이 사전에 프로젝트 구조와 의존성을 분석하고 이해하도록 하며,
그렇지 않으면 불가능한 최적화 작업을 수행합니다.
동일한 명시성은 [SwiftUI 프리뷰](https://developer.apple.com/documentation/swiftui/previews-in-xcode)나 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)와 같은 편집기 기능이 신뢰할 수 있고 예측 가능한 방식으로 동작하도록 보장하는데도 핵심입니다.
Xcode와 Xcode 프로젝트는 편리성을 위해 암시성을 유효한 설계로 채택했기 때문에,
Swift Package Manager도 이 원칙을 계승하였으며,
Xcode를 사용할 때의 어려움이 Swift Package Manager에서도 나타납니다.

> [!INFO] TUIST의 역할
> Tuist의 역할은 프로젝트의 암시적 정의를 방지하고 명시성을 활용해 더 나은 개발자 경험 (예: 검증, 최적화) 을 제공하는 툴로 요약할 수 있습니다. [Bazel](https://bazel.build)과 같은 툴은 이를 한단계 더 발전시켜 빌드 시스템 수준까지 확장합니다.

이 문제는 커뮤니티에서 거의 언급이 되지 않지만, 중요한 문제입니다.
Tuist를 작업하면서,
많은 조직과 개발자들이 현재 직면한 문제를 [Swift Package Manager](https://www.swift.org/documentation/package-manager/)에 의해 해결할 수 있다고 생각하는 것을 발견했지만,
깨닫지 못하는 점은 Swift Package Manager도 동일한 원칙을 기반으로 구축되기 때문에,
잘 알려진 Git 충돌은 해결할 수 있지만,
다른 영역에서 개발자의 경험을 저하시키고 프로젝트 최적화를 어렵게 만든다는 점입니다.

다음 섹션에서 암시적 방식이 개발자 경험과 프로젝트에 어떤 영향을 끼치는지 실제 예제를 통해 다룰 예정입니다. 이 내용이 모든 것을 다루지는 않지만, Xcode 프로젝트나 Swift Package를 작업할 때 직면하는 문제에 대한 해결책을 위한 좋은 아이디어를 제시할 것입니다.

## 편리함이 장애물이 되는 경우 {#convenience-getting-in-your-way}

### 공유된 빌드 결과물 디렉토리 {#shared-built-products-directory}

Xcode는 Derived Data 디렉토리 내에 각 결과물의 디렉토리를 사용합니다.
그 안에는 컴파일된 바이너리, dSYM 파일, 그리고 로그와 같은 빌드 산출물이 저장됩니다.
프로젝트의 모든 결과물이 동일한 디렉토리에 저장되며,
기본적으로 다른 타겟에서 보이기 때문에,
**타겟들이 서로 암시적으로 의존성을 가질 수 있습니다.**
타겟이 적을 경우 문제가 되지 않지만,
프로젝트가 커지면 이것은 빌드 실패로 이어지고 디버깅하기 어려운 상황이 생길 수 있습니다.

이 설계의 결과로 많은 프로젝트는 명확하게 정의되지 않은 그래프로 컴파일 됩니다.

> [!TIP] TUIST의 명시적 의존성 강제
> Tuist는 암시적 의존성을 허용하지 않기 위해 생성 구성 옵션을 제공합니다. 이것을 활성화 하면, 타겟이 명시적으로 선언되지 않은 의존성을 가져오려고 할 때, 빌드는 실패합니다.

### 스킴에서 암시적 의존성 찾기 {#find-implicit-dependencies-in-schemes}

프로젝트 규모가 커질수록 Xcode에서 의존성 그래프를 정의하고 유지하기 어려워집니다.
어려운 이유는 빌드 단계와 빌드 설정이 `.pbxproj` 파일에 코드화 되어 있고,
그래프를 시각화하고 작업할 수 있는 툴이 없으며,
그래프의 변경 사항 (예: 미리 컴파일된 새로운 동적 프레임워크 추가) 이
상위 구성에서의 변경 (예: 번들에 프레임워크를 복사하기 위한 새로운 빌드 단계 추가) 을 요구할 수 있기 때문입니다.

Apple은 어느 시점에 그래프 모델을 더 관리하기 쉬운 형태로 발전시키는 대신에,
빌드 시에 암시적 의존성을 해결하는 옵션을 추가하는 것이 더 합리적이라고 결정하였습니다.
이는 다시 의문점을 남기는데, 빌드 시간이 더 길어지거나 예측할 수 없는 빌드 결과가 나올 수 있기 때문입니다.
예를 들어, 빌드가 로컬에서는 Derive Data의 특정 상태 때문에 정상 동작할 수 있지만,
이 상태는 [singleton](https://en.wikipedia.org/wiki/Singleton_pattern)처럼 동작하므로,
상태가 다른 CI에서는 컴파일이 실패할 수 있습니다.

> [!TIP]
> 우리는 프로젝트 스킴에서 이 기능을 비활성화 하고, 의존성 그래프 관리가 용이한 Tuist 같은 툴을 사용하길 권장합니다.

### SwiftUI 프리뷰와 정적 라이브러리/프레임워크 {#swiftui-previews-and-static-librariesframeworks}

SwiftUI 프리뷰나 Swift Macro와 같은 일부 편집기 기능은 수정된 파일에 의존성 그래프의 컴파일을 필요로 합니다. 편집기의 이런 통합은 빌드 시스템이 모든 암시성을 해결하도록 요구하고 해당 기능이 제대로 동작하도록 올바른 산출물을 출력하도록 요구합니다. 당연히 **그래프가 더 암시적이면 빌드 시스템의 작업은 더 어려워지고**, 이러한 기능 대부분이 제대로 동작하지 않는 것은 놀라운 일이 아닙니다. 개발자들이 SwiftUI 프리뷰가 제대로 동작하지 않아 오래전에 사용을 중지했다는 얘기를 자주 듣습니다. 대신 해당 기능을 사용하기 위해 예제 앱을 사용하거나, 정적 라이브러리나 스크립트 빌드 단계를 사용하는 것을 피해 기능을 사용하고 있습니다.

### Mergeable libraries {#mergeable-libraries}

작업을 더 유연하고 쉽게 하는 동적 프레임워크는 앱의 실행 시간에 안좋은 영향을 줍니다. 반면에, 정적 라이브러리는 더 빠른 실행 시간을 가지지만, 컴파일 시간에 영향을 주고 복잡한 그래프 환경에서 작업하기 어렵게 만듭니다. _구성에 따라 둘 중 하나로 변경할 수 있다면 좋지 않을까요?_
아마 Apple은 Mergeable libraries 작업을 하면서 그 생각을 가졌을 것입니다. 하지만 다시 한 번 Apple은 더 많은 빌드 시간 추론을 빌드 시간으로 옮겼습니다. 의존성 그래프에 대해 추론해야 한다면 타겟의 정적 또는 동적 특성이 일부 타겟의 빌드 설정을 기반으로 빌드 시간이 결정된다고 상상해 봅시다. SwiftUI 프리뷰 기능이 안정적으로 동작하게 하는 것은 쉽지 않습니다.

**많은 사용자가 Mergeable libraries를 사용하기 위해 Tuist를 찾지만 우리의 대답은 항상 같습니다. 그럴 필요가 없습니다.** 생성 시점에 타겟의 정적 또는 동적 특성을 제어할 수 있으며, 이를 통해 컴파일 전에 의존성 그래프를 미리 알 수 있는 프로젝트를 만들 수 있습니다. 빌드 시점에 해결해야 될 변수는 없습니다.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 명시적, 명시적, 그리고 명시적 {#explicit-explicit-and-explicit}

If there's an important non-written principle that we recommend every developer or organization that wants their development with Xcode to scale, is that they should embrace explicitness. And if explicitness is hard to manage with raw Xcode projects, they should consider something else, either [Tuist](https://tuist.io) or [Bazel](https://bazel.build). **Only then reliability, predicability, and optimizations will be possible.**

## Future {#future}

Whether Apple will do something to prevent all the above issues is unknown.
Their continuous decisions embedded into Xcode and the Swift Package Manager don't suggest that they will.
Once you allow implicit configuration as a valid state,
**it's hard to move from there without introducing breaking changes.**
Going back to first principles and rethinking the design of the tools might lead to breaking many Xcode projects that accidentally compiled for years. Imagine the community uproar if that happened.

Apple finds itself in a bit of a chicken-and-egg problem.
Convenience is what helps developers get started quickly and build more apps for their ecosystem.
But their decisions to make the experience convenience at that scale,
is making it hard for them to ensure some of the Xcode features work reliably.

Because the future is unknown,
we try to **be as close as possible to the industry standards and Xcode projects**.
We prevent the above issues,
and leverage the knowledge that we have to provide a better developer experience.
Ideally we wouldn't have to resort to project generation for that,
but the lack of extensibility of Xcode and the Swift Package Manager make it the only viable option.
And it's also a safe option because they'll have to break the Xcode projects to break Tuist projects.

Ideally, **the build system was more extensible**,
but wouldn't it be a bad idea to have plugins/extensions that contract with a world of implicitness?
It doesn't seem like a good idea.
So it seems like we'll need external tools like Tuist or [Bazel](https://bazel.build) to provide a better developer experience.
Or maybe Apple will surprise us all and make Xcode more extensible and explicit...

Until that happens, you have to choose whether you want to embrace the convencience of Xcode and take on the debt that comes with it, or trust us on this journey to provide a better developer experience.
We won't disappoint you.
