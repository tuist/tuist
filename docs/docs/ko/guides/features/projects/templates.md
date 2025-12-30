---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# 템플릿 {#templates}

아키텍처가 확립된 프로젝트에서 개발자는 프로젝트와 일관된 새 컴포넌트나 기능을 부트스트랩하고 싶을 수 있습니다. ` 튜이스트 스캐폴드`
템플릿에서 파일을 생성할 수 있습니다. 직접 템플릿을 정의하거나 튜이스트에서 제공하는 템플릿을 사용할 수 있습니다. 다음은 스캐폴딩이 유용할 수
있는 몇 가지 시나리오입니다:

- 주어진 아키텍처를 따르는 새 기능을 만듭니다: `tuist scaffold viper --name MyFeature`.
- 새 프로젝트 만들기: `튜스트 스캐폴드 기능 프로젝트 --이름 홈`

::: info NON-OPINIONATED
<!-- -->
Tuist는 템플릿의 콘텐츠와 템플릿의 용도에 대해 의견을 제시하지 않습니다. 템플릿은 특정 디렉토리에만 있어야 합니다.
<!-- -->
:::

## 템플릿 정의하기 {#defining-a-template}

템플릿을 정의하려면 <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>를 실행한 다음 `Tuist/Templates` 아래에 템플릿을 나타내는 `name_of_template`
라는 디렉터리를 생성하면 됩니다. 템플릿에는 템플릿을 설명하는 매니페스트 파일( `name_of_template.swift` )이 필요합니다.
따라서 `framework` 라는 템플릿을 만드는 경우 `Tuist/Templates` 에 `framework` 라는 새 디렉터리를 만들고
`framework.swift` 라는 매니페스트 파일을 만들어야 합니다:


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

템플릿을 정의한 후에는 `scaffold` 명령어에서 템플릿을 사용할 수 있습니다:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

::: info Mise란?
<!-- -->
플랫폼은 선택적 인자이므로 `--platform macos` 인수 없이 명령을 호출할 수도 있습니다.
<!-- -->
:::

`.문자열` 및 `.파일` 이 충분한 유연성을 제공하지 않는 경우 `.파일` 케이스를 통해
[스텐실](https://stencil.fuller.li/en/latest/) 템플릿 언어를 활용할 수 있습니다. 그 외에도 여기에 정의된 추가
필터를 사용할 수도 있습니다.

문자열 보간을 사용하면 위의 `\(nameAttribute)` 은 `{{ name }}` 으로 해석됩니다. 템플릿 정의에서 스텐실 필터를
사용하려는 경우 해당 보간을 수동으로 사용하고 원하는 필터를 추가할 수 있습니다. 예를 들어 `{ { 이름 | 소문자 } }을 사용할 수
있습니다. ` \(nameAttribute)` 대신` 를 사용하여 이름 속성의 소문자 값을 가져올 수 있습니다.

전체 폴더를 지정된 경로에 복사할 수 있는 `.디렉토리` 를 사용할 수도 있습니다.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
템플릿은 <LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명 도우미</LocalizedLink>를 사용하여 여러 템플릿에서 코드를 재사용할 수 있도록 지원합니다.
<!-- -->
:::
