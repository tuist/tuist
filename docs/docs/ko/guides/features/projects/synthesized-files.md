---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# 합성된 파 {#synthesized-files}

Tuist는 생성할 때 프로젝트를 관리하고 작업하기 위한 몇 가지 규칙을 파일과 코드를 생성할 수 있습니다. 이 페이지에서 이러한 기능에 대해
배우면 여러분의 프로젝트에서 사용할 수 있게 될 것 입니다.

## Target 리소스 {#target-resources}

Xcode 프로젝트는 Target에 리소스 추가를 지원하지만, 팀에게 몇 가지 문제를 안겨줍니다, 특히 소스와 리소스가 종종 옮겨지는 모듈화된
프로젝트를 가지고 작업할 때 발생 합니다:

- **비일관적인 실행 중 접근**: 최종 제품에 있는 Resource의 위치와 거기에 어떻게 접근하는 지는 Target 제품에 달렸습니다.
  예를 들어, 여러분의 Target이 어플리케이션을 나타낸다면, Resource는 어플리케이션 Bundle에 복제 됩니다. 이러면 코드가
  Bundle 구조를 가정하는 Resource에 접근할 수 있게 되는데, 이상적이진 않습니다, 이렇게 하면 코드를 분석하기 어렵게 만들고
  Resource를 멀리 이동하지 못하게 만들기 때문 입니다.
- **Resource를 지원하지 않는 제품**: 번들화 되지 않아서 Resource를 지원하지 못하는 Static 라이브러리 같은 제품이
  있습니다. 그런 이유로, 여러분은 다른 제품 Type으로 변경 해야 하던지 해야 합니다, 예를 들어서 여러분의 프로젝트나 앱에 몇 가지
  과도한 작업이 추가될 수도 있는 Framework로 말이죠. 예를 들어서, Static Framework는 고정적으로 최종 제품에 연결 될
  것 이고 Build Phase는 Resource를 최종 제품에 복사하는데만 필요로 합니다. 아니면 Xcode가 Binary와 Resource
  둘 다 최종 제품으로 복사할 동적 Framework, 하지만 그것은 앱의 시작 시간을 증가 시킵니다, Framework가 동적으로 불러와질
  필요가 있기 때문입니다.
- **잦은 런타임 오류**: 리소스는 이름과 확장자(문자열)로 식별 되어서 이 중 하나라도 오타가 있으면 리소스에 액세스하려고 할 때 런타임
  오류가 발생합니다. 이는 컴파일 할 때 감지되지 않고 배포 후에 충돌을 일으킬 수 있으므로 이상적이지 않습니다.

Tuist는 이러한 문제를 구현 세부 사항을 추상화한 **번들 및 리소스에 액세스할 수 있는 통합 인터페이스를 합성**하여 해결합니다.

::: warning 권장사항
<!-- -->
Tuist 통합 인터페이스를 통해 리소스에 액세스하는 것이 필수가 아닐지라도, 코드를 더 쉽게 이해하고 리소스를 이동하기 쉽게 해주기 때문에
이를 권장합니다.
<!-- -->
:::

## 리소스 {#resources}

Tuist는 `Info.plist`나 Entitlement 같은 파일의 내용을 Swift로 선언하는 인터페이스를 제공하는데, 이는 Target과
프로젝트 전반에서 일관성을 보장하고 컴파일 시 컴파일러를 활용하여 문제를 파악하는 데 유용합니다. 또한 이 내용을 모델링하고 여러 대상과
프로젝트에 공유하기 위해 여러분만의 추상화를 만들어 낼 수도 있습니다.

프로젝트가 생성되면, Tuist는 해당 파일의 콘텐츠를 합성하여 해당 파일을 정의하는 프로젝트가 포함된 경로에 있는`Derived` 디렉터리에
작성합니다.

::: tip Derived 디렉토리를 무시하세요
<!-- -->
프로젝트의 `.gitignore` 파일에 `Derived` 디렉터리 추가를 권장 합니다.
<!-- -->
:::

## 번들 접근자 {#bundle-accessors}

Tuist는 Target 리소스를 포함하는 번들에 접근하기 위한 인터페이스를 합성합니다.

### Swift {#swift}

Target은 번들을 노출하는 `Bundle` Type의 Extension을 가질 것 입니다:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C에는 번들에 접근할 수 있는 `{Target 이}Resources` 인터페이스를 제공합니다:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning 내부 Target 제한
<!-- -->
현재 Tuist는 Objective-C 소스만 가지는 내부 Target에 대한 Resource 번들 접근자를 생성하지 않는데, [이슈
#6456](https://github.com/tuist/tuist/issues/6456)에서 보고되어 알려진 제한 사항입니다.
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
예를 들어 라이브러리와 같은 대상 제품이 리소스를 지원하지 않는 경우, Tuist는 리소스가 최종 제품에 포함되고 인터페이스가 올바른 번들을
가리키도록 하기 위해 `번들` 제품 유형의 대상에 리소스를 포함시킵니다.
<!-- -->
:::

## 리소스 접근자 {#resource-accessors}

리소스는 문자열을 사용하여 이름과 확장자로 식별됩니다. 이는 컴파일 시 포착되지 않고 릴리스 시 충돌을 일으킬 수 있으므로 이상적이지 않습니다.
이를 방지하기 위해 Tuist는 프로젝트 생성 프로세스에
[SwiftGen](https://github.com/SwiftGen/SwiftGen)을 통합하여 리소스에 액세스할 수 있는 인터페이스를
합성합니다. 덕분에 컴파일러를 활용하여 리소스에 자신 있게 액세스하여 문제를 포착할 수 있습니다.

Tuist에는 기본적으로 다음 리소스 유형에 대한 접근자를 합성하는
[템플릿](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)이
포함되어 있습니다:

| 리소스 유형   | 합성된 파일                  |
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

::: info REFERENCE
<!-- -->
사용자 지정 템플릿을 사용하여 리소스에 대한 액세스자를 합성하는 방법의 예는 [이 수정
사항](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)에서
확인할 수 있습니다.
<!-- -->
:::
