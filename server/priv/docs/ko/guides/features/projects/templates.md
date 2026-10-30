---
{
  "title": "템플릿",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist에서 템플릿을 생성하고 사용하여 프로젝트 코드를 생성하는 방법을 알아보세요."
}
---
# 템플릿 {#templates}

아키텍처가 정립된 프로젝트에서는 개발자가 프로젝트와 일관된 새 컴포넌트나 기능을 부트스트랩하기를 원할 수 있습니다. `tuist scaffold`를 사용하면 템플릿에서 파일을 생성할 수 있습니다. 자체 템플릿을 정의하거나 Tuist에 포함된 템플릿을 사용할 수 있습니다. 스캐폴딩이 유용한 몇 가지 시나리오는 다음과 같습니다:

- 주어진 아키텍처를 따르는 새 기능 만들기: `tuist scaffold viper --name MyFeature`.
- 새 프로젝트 만들기: `tuist scaffold feature-project --name Home`

> [!NOTE]
> **주관이 개입되지 않음**
>
> Tuist는 템플릿의 내용과 용도에 대해 특정 방식을 강요하지 않습니다. 템플릿은 특정 디렉터리에 위치하기만 하면 됩니다.


## 템플릿 정의하기 {#defining-a-template}

템플릿을 정의하려면 <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>를 실행한 후, 템플릿을 나타내는 `name_of_template`라는 디렉터리를 `Tuist/Templates` 아래에 생성하세요. 템플릿에는 템플릿을 설명하는 매니페스트 파일인 `name_of_template.swift`이 필요합니다. 따라서 `framework`이라는 템플릿을 생성한다면, `Tuist/Templates`에 `framework`이라는 새 디렉터리를 만들고 `framework.swift`이라는 매니페스트 파일을 만들어야 하며, 그 내용은 다음과 같을 수 있습니다:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## 템플릿 사용하기 {#using-a-template}

템플릿을 정의한 후에는 `scaffold` 명령어를 통해 사용할 수 있습니다:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]
> platform은 선택적 인수이므로 `--platform macos` 인수 없이도 명령어를 호출할 수 있습니다.


`.string`와 `.files`로 충분한 유연성을 확보하기 어렵다면, `.file` 케이스를 통해 [Stencil](https://stencil.fuller.li/en/latest/) 템플릿 언어를 활용할 수 있습니다. 또한 여기에 정의된 추가 필터를 사용할 수도 있습니다.

문자열 보간법을 사용하면 위의 `\(nameAttribute)`는 `{{ name }}`로 해석됩니다. 템플릿 정의에서 Stencil 필터를 사용하려면 해당 보간법을 수동으로 사용하고 원하는 필터를 추가하면 됩니다. 예를 들어, name 속성의 소문자 값을 얻기 위해 `\(nameAttribute)` 대신 `{ { name | lowercase } }`를 사용할 수 있습니다.

전체 폴더를 지정된 경로로 복사할 수 있는 `.directory`도 사용할 수 있습니다.

> [!TIP]
> **Project Description Helpers**
>
> 템플릿은 <.localized_link href="/guides/features/projects/code-sharing">프로젝트 설명 헬퍼</.localized_link>를 사용하여 템플릿 간에 코드를 재사용하는 것을 지원합니다.
