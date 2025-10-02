---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# 합성된 파일 {#합성된 파일}

Tuist는 생성 시점에 파일과 코드를 생성하여 Xcode 프로젝트를 관리하고 작업하는 데 편리함을 더할 수 있습니다. 이 페이지에서는 이
기능에 대해 알아보고 프로젝트에서 이 기능을 사용하는 방법을 알아봅니다.

## 대상 리소스 {#target-resources}

Xcode 프로젝트는 대상에 리소스를 추가하는 기능을 지원합니다. 그러나 특히 소스와 리소스가 자주 이동하는 모듈식 프로젝트로 작업할 때 팀에
몇 가지 과제를 제시합니다:

- **일관되지 않은 런타임 액세스**: 최종 제품에서 리소스가 최종적으로 어디에 위치하며 어떻게 액세스하는지는 대상 제품에 따라 다릅니다.
  예를 들어 타깃이 애플리케이션을 나타내는 경우 리소스는 애플리케이션 번들에 복사됩니다. 이렇게 하면 번들 구조에 대한 가정을 기반으로
  리소스에 액세스하는 코드가 생성되는데, 이는 코드를 추론하기 어렵고 리소스를 이동하기 어렵게 만들기 때문에 이상적이지 않습니다.
- **리소스를 지원하지 않는 제품**: 정적 라이브러리와 같이 번들이 아니므로 리소스를 지원하지 않는 특정 제품이 있습니다. 따라서 프로젝트나
  앱에 약간의 오버헤드가 추가될 수 있는 다른 제품 유형(예: 프레임워크)을 사용해야 합니다. 예를 들어 정적 프레임워크는 최종 제품에
  정적으로 연결되며 빌드 단계에서 리소스를 최종 제품에 복사하는 데만 필요합니다. 또는 동적 프레임워크의 경우 Xcode가 바이너리와 리소스를
  모두 최종 제품에 복사하지만 프레임워크를 동적으로 로드해야 하므로 앱의 시작 시간이 늘어날 수 있습니다.
- **런타임 오류가 발생하기 쉽습니다**: 리소스는 이름과 확장자(문자열)로 식별됩니다. 따라서 이 중 하나라도 오타가 있으면 리소스에
  액세스하려고 할 때 런타임 오류가 발생합니다. 이는 컴파일 시점에 포착되지 않고 릴리스에서 충돌을 일으킬 수 있으므로 이상적이지 않습니다.

Tuist는 위의 문제를 해결하기 위해 **구현 세부 사항을 추상화한 번들 및 리소스(** )에 액세스할 수 있는 통합 인터페이스를 합성하여
해결합니다.

> [중요] 권장 Tuist 통합 인터페이스를 통해 리소스에 액세스하는 것이 필수는 아니지만, 코드를 더 쉽게 추론하고 리소스를 이동하기 쉽기
> 때문에 권장합니다.

## 리소스 {#자원}

Tuist는 `Info.plist` 또는 자격과 같은 파일의 내용을 Swift로 선언하는 인터페이스를 제공합니다. 이는 타깃과 프로젝트 전반에서
일관성을 보장하고 컴파일 시 컴파일러를 활용하여 문제를 파악하는 데 유용합니다. 또한 콘텐츠를 모델링하고 여러 대상과 프로젝트에서 공유하기 위해
자체 추상화를 만들 수도 있습니다.

프로젝트가 생성되면 Tuist는 해당 파일의 콘텐츠를 합성하여 해당 파일을 정의하는 프로젝트가 포함된 디렉터리를 기준으로 `Derived`
디렉터리에 작성합니다.

> [!팁] 파생된 디렉터리 GITIGNORE 프로젝트의 `.gitignore` 파일에 `파생된` 디렉터리를 추가하는 것이 좋습니다.

## 번들 액세스 권한 {#번들-액세서}

Tuist는 대상 리소스가 포함된 번들에 액세스할 수 있는 인터페이스를 합성합니다.

### Swift {#swift}

대상에는 번들을 노출하는 `번들` 유형의 확장자가 포함됩니다:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C에서는 번들에 액세스할 수 있는 `{Target}Resources` 인터페이스가 제공됩니다:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!경고] 내부 대상에 대한 제한 현재 Tuist는 Objective-C 소스만 포함된 내부 대상에 대한 리소스 번들 접근자를 생성하지
> 않습니다. 이는 [이슈 #6456](https://github.com/tuist/tuist/issues/6456)에서 추적된 알려진 제한
> 사항입니다.

> [!팁] 번들을 통해 라이브러리에서 리소스 지원 라이브러리와 같은 대상 제품이 리소스를 지원하지 않는 경우, Tuist는 해당 리소스가 최종
> 제품에 포함되고 인터페이스가 올바른 번들을 가리키도록 하기 위해 제품 유형 `번들` 의 대상에 리소스를 포함시킵니다.

## 리소스 액세스자 {#자원-액세스자}

리소스는 문자열을 사용하여 이름과 확장자로 식별됩니다. 이는 컴파일 시 포착되지 않고 릴리스 시 충돌을 일으킬 수 있으므로 이상적이지 않습니다.
이를 방지하기 위해 Tuist는 프로젝트 생성 프로세스에
[SwiftGen](https://github.com/SwiftGen/SwiftGen)을 통합하여 리소스에 액세스할 수 있는 인터페이스를
합성합니다. 덕분에 컴파일러를 활용하여 리소스에 자신 있게 액세스하여 문제를 포착할 수 있습니다.

Tuist에는 기본적으로 다음 리소스 유형에 대한 접근자를 합성하는
[템플릿](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)이
포함되어 있습니다:

| 리소스 유형   | Synthesized files       |
| -------- | ----------------------- |
| 이미지 및 색상 | `Assets+{Target}.swift` |
| 문자열      | `문자열+{Target}.swift`    |
| 목록       | `{NameOfPlist}.swift`   |
| 글꼴       | `Fonts+{Target}.swift`  |
| 파일       | `Files+{Target}.swift`  |

> 참고: 프로젝트별 리소스 접근자 합성을 비활성화하려면 프로젝트 옵션에 `disableSynthesizedResourceAccessors`
> 옵션을 전달하여 프로젝트별로 리소스 접근자 합성을 비활성화할 수 있습니다.

#### 사용자 지정 템플릿 {#custom-templates}

SwiftGen](https://github.com/SwiftGen/SwiftGen)에서 지원해야 하는 다른 리소스 유형에 대한 접근자를
합성하기 위해 자체 템플릿을 제공하려는 경우 `Tuist/ResourceSynthesizers/{name}.stencil` 에서 만들 수
있으며, 여기서 이름은 리소스의 대소문자 버전입니다.

| 리소스      | 템플릿 이름             |
| -------- | ------------------ |
| 문자열      | `문자열.스텐실`          |
| 자산       | `Assets.stencil`   |
| 목록       | `Plists.stencil`   |
| 글꼴       | `Fonts.stencil`    |
| 핵심 데이터   | `CoreData.stencil` |
| 인터페이스 빌더 | `인터페이스 빌더 스텐실`     |
| json     | `JSON.stencil`     |
| yaml     | `YAML.stencil`     |
| 파일       | `Files.stencil`    |

접근자를 합성할 리소스 유형 목록을 구성하려면 `Project.resourceSynthesizers` 프로퍼티에 사용하려는 리소스 합성기 목록을
전달하면 됩니다:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

> [참고 [이 수정
> 사항](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)에서
> 사용자 지정 템플릿을 사용하여 리소스에 대한 액세스자를 합성하는 방법에 대한 예시를 확인할 수 있습니다.
