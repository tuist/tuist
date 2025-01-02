---
title: Synthesized files
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Tuist 프로젝트에서 자동으로 생성된 파일에 대해 배워봅니다.
---

# Synthesized files {#synthesized-files}

Tuist는 Xcode 프로젝트를 관리하고 작업할 때 편의성을 가지기 위해 생성 시점에 파일과 코드를 생성할 수 있습니다. 이 문서에서는 해당 기능에 대해 배우고 프로젝트에서 어떻게 사용하는지 배워봅니다.

## 타겟 리소스 {#target-resources}

Xcode 프로젝트는 타겟에 리소스 추가를 지원합니다. 그러나 이것은 소스와 리소스를 자주 이동하는 모듈화된 프로젝트를 작업할 때 팀에 몇가지 과제를 제시합니다:

- **일관되지 않은 런타인 접근**: 리소스가 최종 결과물에서 어떻게 포함되고 리소스에 접근하는 방식은 타겟 결과물에 따라 다릅니다. 예를 들어, 타겟이 애플리케이션인 경우, 리소스는 애플리케이션 번들에 복사됩니다. 이것으로 인해 리소스 접근하는 코드가 번들 구조에 대해 가정을 하게 되고, 이것은 코드의 이해를 어렵게 하고 리소스 이동을 복잡하게 만들기 때문에 이상적이지 않습니다.
- **리소스를 지원하지 않는 결과물**: 정적 라이브러리와 같이 번들이 아닌 특정 제품은 리소스를 지원하지 않습니다. 그렇기 때문에 프로젝트나 앱에 오버헤드를 추가할 수 있는 프레임워크와 같은 다른 결과물 타입을 사용해야 할 수도 있습니다. 예를 들어, 정적 프레임워크는 최종 결과물에 정적으로 연결되고 최종 결과물에 리소스를 복사하기 위한 빌드 단계가 필요합니다. 또는 동적 프레임워크는 Xcode가 최종 결과물에 바이너리와 리소스를 모두 복사하지만 프레임워크를 동적으로 로드해야 하므로 앱의 시작 시간이 증가합니다.
- **런타임 오류가 발생하기 쉬움**: 리소스는 이름과 확장자 (문자열) 로 구분됩니다. 따라서 이 중에 오타가 있으면 리소스에 접근할 때 런타임 오류가 발생합니다. 이 방법은 컴파일 시점에 발견되지 않아 이상적인 방법이 아니며, 릴리즈 때 크래시가 발생할 수 있습니다.

Tuist는 구현 세부 사항을 추상화하여 **번들과 리소스에 접근하기 위한 통합된 인터페이스를 자동으로 생성**하여 위의 문제를 해결합니다.

> [!IMPORTANT] 권장
> Tuist가 자동으로 생성하는 인터페이스를 통해 리소스에 접근하는 방식은 필수가 아니지만, 코드를 쉽게 추론할 수 있고 리소스 이동에 용이하므로 권장합니다.

## 리소스 {#resources}

Tuist는 `info.plist`나 entitlement와 같은 파일의 내용을 Swift로 선언할 수 있는 인터페이스를 제공합니다.
이것은 타겟과 프로젝트의 일관성을 유지하고,
컴파일 시 문제를 파악하는데 유용합니다.
또한 내용을 모델링하기 위해 추상화를 만들어 이를 여러 타겟과 프로젝트에 공유할 수도 있습니다.

프로젝트가 생성될 때,
Tuist는 해당 파일의 내용을 합성하여 프로젝트가 포함된 디렉토리를 기준으로 `Derived` 디렉토리에 작성합니다.

> [!TIP] DERIVED 디렉토리 GITIGNORE
> 프로젝트의 `.gitignore` 파일에 `Derived` 디렉토리를 추가하길 권장합니다.

## 번들 접근자 {#bundle-accessors}

Tuist는 타겟 리소스를 포함하는 번들에 접근하기 위해 자동으로 인터페이스를 생성합니다.

### Swift {#swift}

타겟은 번들을 노출하는 `Bundle` 타입의 확장자를 포함합니다:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C에서 번들에 접근하기 위해 `{Target}Resources` 인터페이스가 있습니다.

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!TIP] 번들로 라이브러리 리소스 지원
> 예를 들어, 라이브러리와 같이 타겟 결과물이 리소스를 지원하지 않으면, Tuist는 `bundle` 타입의 타겟에 리소스를 포함시켜 최종 결과물에 포함시키고 인터페이스가 올바른 번들을 가리키도록 보장합니다.

## 리소스 접근자 {#resource-accessors}

리소스는 문자열을 사용하여 이름과 확장자로 구분됩니다. 이 방법은 컴파일 시점에 발견되지 않아 이상적인 방법이 아니며, 릴리즈 때 크래시가 발생할 수 있습니다. 이것을 방지하기 위해 Tuist는 [SwiftGen](https://github.com/SwiftGen/SwiftGen)을 프로젝트 생성 과정에 통합하여 리소스를 접근하기 위한 인터페이스를 자동으로 생성합니다. 덕분에 컴파일러를 활용하여 리소스 접근을 보장하고 문제를 파악할 수 있습니다.

Tuist는 기본적으로 다음의 리소스에 대한 접근자를 자동으로 생성하기 위해 [템플릿](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)을 포함합니다.

| Resource type | Synthesized file         |
| ------------- | ------------------------ |
| 이미지와 색상       | `Assets+{Target}.swift`  |
| Strings       | `Strings+{Target}.swift` |
| Plists        | `{NameOfPlist}.swift`    |
| Fonts         | `Fonts+{Target}.swift`   |
| Files         | `Files+{Target}.swift`   |

> Note: 프로젝트 기준으로 리소스 접근자의 자동 생성을 비활성화 하려면 프로젝트 옵션에 `disableSynthesizedResourceAccessors` 옵션을 추가하면 됩니다.

#### 사용자 정의 템플릿 {#custom-templates}

[SwiftGen](https://github.com/SwiftGen/SwiftGen)이 지원하는 다른 리소스 타입에 대해 접근자를 템플릿으로 제공하려면 리소스의 카멜-케이스 이름으로 `Tuist/ResourceSynthesizers/{name}.stencil`을 생성할 수 있습니다.

| Resource         | Template name              |
| ---------------- | -------------------------- |
| strings          | `Strings.stencil`          |
| assets           | `Assets.stencil`           |
| plists           | `Plists.stencil`           |
| fonts            | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| files            | `Files.stencil`            |

접근자에 리소스 타입의 목록을 구성하려면,
`Project.resourceSynthesizers` 프로퍼티를 사용하여 사용하려는 리소스 타입을 넘겨주면 됩니다:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE] 참조
> 리소스 접근자를 자동 생성하기 위해 어떻게 사용자 정의된 템플릿을 사용하는지 확인하려면 [이 예제](https://github.com/tuist/tuist/tree/main/fixtures/ios_app_with_templates)에서 확인할 수 있습니다.
