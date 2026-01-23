---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# 템플릿 {#templates}

확립된 아키텍처를 가진 프로젝트에서 개발자는 프로젝트와 일관된 새로운 컴포넌트나 기능을 부트스트랩하고 싶어 할 수 있습니다. ` ``
또는 `tuist scaffold` `을 사용하면 템플릿으로부터 파일을 생성할 수 있습니다. 자체 템플릿을 정의하거나 Tuist에 포함된
템플릿을 사용할 수 있습니다. 스캐폴딩이 유용할 수 있는 몇 가지 시나리오는 다음과 같습니다:

- 주어진 아키텍처를 따르는 새 기능을 생성하세요: `tuist scaffold viper --name MyFeature`
- 새 프로젝트 생성: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist는 템플릿의 내용이나 사용 목적에 대해 특정 방식을 강요하지 않습니다. 단지 특정 디렉토리에 위치해야 할 뿐입니다.
<!-- -->
:::

## 템플릿 정의하기 {#defining-a-template}

템플릿을 정의하려면 <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> 를 실행한 후, `Tuist/Templates` 아래에 템플릿을 나타내는
`name_of_template` 디렉터리를 생성하세요. 템플릿에는 `name_of_template.swift` 템플릿을 설명하는 매니페스트
파일이 필요합니다. 따라서 `framework` 라는 템플릿을 생성하는 경우, `Tuist/Templates` 아래에 `framework` 라는
새 디렉터리를 생성하고 매니페스트 파일 `framework.swift` 을 포함시켜야 합니다. 매니페스트 파일은 다음과 같이 구성될 수
있습니다:


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

## 템플릿 사용 {#using-a-template}

템플릿을 정의한 후에는 ` `` 스캐폴드 명령어(` )에서 사용할 수 있습니다:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info Mise란?
<!-- -->
platform은 선택적 인자이므로, `--platform macos` 인자 없이도 명령어를 호출할 수 있습니다.
<!-- -->
:::

`.string` 및 `.files` 가 충분한 유연성을 제공하지 않는다면, `.file` 의 경우
[Stencil](https://stencil.fuller.li/en/latest/) 템플릿 언어를 활용할 수 있습니다. 또한 여기에 정의된
추가 필터를 사용할 수도 있습니다.

문자열 보간을 사용하면, `\(nameAttribute)` 위의 코드는 `{{ name }}` 로 해석됩니다. 템플릿 정의에서 Stencil
필터를 사용하려면, 해당 보간을 수동으로 활용하여 원하는 필터를 추가할 수 있습니다. 예를 들어, `\(nameAttribute)` 대신 `{
{ name | lowercase } }` 를 사용하면 name 속성의 소문자 값을 얻을 수 있습니다.

`.directory` 를 사용하면 지정된 경로로 전체 폴더를 복사할 수 있습니다.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
템플릿은 <LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명
헬퍼</LocalizedLink>를 사용하여 템플릿 간 코드 재사용을 지원합니다.
<!-- -->
:::
