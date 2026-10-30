---
{
  "title": "생성된 파일",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 프로젝트에서 생성된 파일에 대해 알아보세요."
}
---
# 생성된 파일 {#synthesized-files}

Tuist는 생성 시점에 파일과 코드를 생성하여 Xcode 프로젝트를 관리하고 작업하는 데 편의를 제공합니다. 이 페이지에서는 이 기능과 프로젝트에서 사용하는 방법을 알아봅니다.

## 타겟 리소스 {#target-resources}

Xcode 프로젝트는 타겟에 리소스를 추가하는 것을 지원합니다. 하지만 특히 소스와 리소스가 자주 이동되는 모듈형 프로젝트에서 작업할 때 몇 가지 어려움이 발생합니다:

- **런타임 접근의 일관성 부족**: 리소스가 최종 제품에 어디에 배치되고 어떻게 접근하는지는 타겟 제품에 따라 다릅니다. 예를 들어 타겟이 애플리케이션을 나타내면 리소스는 애플리케이션 번들에 복사됩니다. 이로 인해 리소스에 접근하는 코드가 번들 구조에 대한 가정을 하게 되며, 이는 코드의 추론을 어렵게 하고 리소스 이동을 복잡하게 하므로 이상적이지 않습니다.
- **리소스를 지원하지 않는 제품 유형**: 정적 라이브러리와 같이 번들이 아닌 특정 제품 유형은 리소스를 지원하지 않습니다. 따라서 프레임워크와 같은 다른 제품 유형을 사용해야 할 수 있으며, 이는 프로젝트나 앱에 오버헤드를 추가할 수 있습니다. 예를 들어 정적 프레임워크는 최종 제품에 정적으로 링크되며, 리소스만 최종 제품에 복사하려면 빌드 단계가 필요합니다. 동적 프레임워크의 경우 Xcode가 바이너리와 리소스를 모두 최종 제품에 복사하지만, 프레임워크를 동적으로 로드해야 하므로 앱의 시작 시간이 증가합니다.
- **런타임 오류 발생 가능성**: 리소스는 이름과 확장자(문자열)로 식별됩니다. 따라서 이러한 값 중 하나라도 오타가 있으면 리소스에 접근할 때 런타임 오류가 발생합니다. 컴파일 시간에 발견되지 않고 릴리스 버전에서 충돌을 유발할 수 있으므로 이상적이지 않습니다.

Tuist는 구현 세부 사항을 추상화하는 **번들 및 리소스에 접근하기 위한 통합 인터페이스를 생성**하여 위의 문제를 해결합니다.

> [!WARNING]
> **권장 사항**
>
> Tuist가 생성한 인터페이스를 통해 리소스에 접근하는 것이 필수 사항은 아니지만, 코드의 추론을 쉽게 하고 리소스 이동을 간편하게 하므로 이를 권장합니다.


## 리소스 {#resources}

Tuist는 Swift에서 `Info.plist` 또는 entitlements와 같은 파일의 콘텐츠를 선언하기 위한 인터페이스를 제공합니다. 이는 타겟과 프로젝트 간 일관성을 보장하고 컴파일러를 활용해 컴파일 시간에 문제를 발견하는 데 유용합니다. 또한 콘텐츠 모델을 자체적으로 추상화하여 타겟과 프로젝트 간에 공유할 수도 있습니다.

프로젝트가 생성되면 Tuist는 해당 파일의 콘텐츠를 생성하고 이를 정의한 프로젝트가 포함된 디렉터리를 기준으로 한 `Derived` 디렉터리에 작성합니다.

> [!TIP]
> **Derived 디렉터리를 Gitignore에 추가**
>
> 프로젝트의 `.gitignore` 파일에 `Derived` 디렉터리를 추가하는 것을 권장합니다.


## 번들 접근자 {#bundle-accessors}

Tuist는 타겟 리소스를 포함하는 번들에 접근하기 위한 인터페이스를 생성합니다.

### Swift {#swift}

타겟에는 번들을 노출하는 `Bundle` 타입의 확장자가 포함됩니다:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C에서는 번들에 접근하기 위해 `{Target}Resources` 인터페이스를 사용합니다:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **Internal 타겟의 제한 사항**
>
> 현재 Tuist는 Objective-C 소스만 포함하는 internal 타겟에 대해 리소스 번들 접근자를 생성하지 않습니다. 이는 [issue #6456](https://github.com/tuist/tuist/issues/6456)에서 추적 중인 알려진 제한 사항입니다.


> [!TIP]
> **번들을 통한 라이브러리의 리소스 지원**
>
> 라이브러리와 같은 타겟 제품이 리소스를 지원하지 않으면, Tuist는 리소스를 제품 유형이 `bundle`인 타겟에 포함시켜 최종 제품에 제대로 배치되고 인터페이스가 올바른 번들을指向하도록 합니다. 이렇게 생성된 번들은 자동으로 `tuist:synthesized` 태그가 지정되며 부모 타겟의 모든 태그를 상속받아 <.localized_link href="/guides/features/projects/metadata-tags#system-tags">캐시 프로필</.localized_link>에서 대상으로 지정할 수 있습니다.


## 리소스 접근자 {#resource-accessors}

리소스는 문자열을 사용하여 이름과 확장자로 식별됩니다. 이는 컴파일 시간에 발견되지 않고 릴리스 버전에서 충돌을 유발할 수 있으므로 이상적이지 않습니다. 이를 방지하기 위해 Tuist는 프로젝트 생성 과정에 [SwiftGen](https://github.com/SwiftGen/SwiftGen)을 통합하여 리소스에 접근하기 위한 인터페이스를 생성합니다. 이를 통해 컴파일러를 활용해 문제를 사전에 발견하며 안심하고 리소스에 접근할 수 있습니다.

Tuist는 기본적으로 다음 리소스 유형에 대한 접근자를 생성하기 위한 [템플릿](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates)을 포함합니다:

| 리소스 유형 | 생성된 파일 |
| --- | ---- |
| 이미지 및 색상 | `Assets+{Target}.swift` |
| 문자열 | `Strings+{Target}.swift` |
| Plist | `{NameOfPlist}.swift` |
| 폰트 | `Fonts+{Target}.swift` |
| 파일 | `Files+{Target}.swift` |

> 참고: 프로젝트 옵션에 `disableSynthesizedResourceAccessors` 옵션을 전달하면 프로젝트별로 리소스 접근자 생성을 비활성화할 수 있습니다.

#### 사용자 정의 템플릿 {#custom-templates}

[SwiftGen](https://github.com/SwiftGen/SwiftGen)이 지원하는 다른 리소스 유형에 대한 접근자를 생성하기 위해 자체 템플릿을 제공하려면, 리소스의 카멜케이스 이름을 사용한 `Tuist/ResourceSynthesizers/{name}.stencil` 경로에 템플릿을 생성하면 됩니다.

| 리소스 | 템플릿 이름 |
| --- | --- |
| 문자열 | `Strings.stencil` |
| 자산 | `Assets.stencil` |
| plist | `Plists.stencil` |
| 폰트 | `Fonts.stencil` |
| Core Data | `CoreData.stencil` |
| Interface Builder | `InterfaceBuilder.stencil` |
| JSON | `JSON.stencil` |
| YAML | `YAML.stencil` |
| 파일 | `Files.stencil` |

접근자를 생성할 리소스 유형 목록을 구성하려면, 사용할 리소스 생성기 목록을 전달하는 `Project.resourceSynthesizers` 속성을 사용하면 됩니다:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [!NOTE]
> **참조**
>
> 사용자 정의 템플릿을 사용하여 리소스에 대한 접근자를 생성하는 방법을 확인하려면 [이 예제](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)를 참고하세요.
