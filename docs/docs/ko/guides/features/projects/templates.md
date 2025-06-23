---
title: Templates
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: 프로젝트에서 코드 생성을 위해 Tuist에서 템플릿을 생성하고 사용하는 방법을 배워봅니다.
---

# Templates {#templates}

기존 아키텍처가 있는 프로젝트에서 개발자가 프로젝트와 일관성 있는 새로운 컴포넌트나 기능을 부트스트랩 하고 싶을 수 있습니다. `tuist scaffold`를 사용하면 템플릿에서 파일을 생성할 수 있습니다. 템플릿을 정의할 수도 있고, Tuist에서 제공하는 템플릿을 사용할 수도 있습니다. 스캐폴딩 (Scaffolding) 이 유용한 몇가지 시나리오가 있습니다:

- 주어진 아키텍처를 따르는 새로운 기능을 생성: `tuist scaffold viper --name MyFeature`.
- 새로운 프로젝트 생성: `tuist scaffold feature-project --name Home`

> [!NOTE] NON-OPINIONATED
> Tuist는 템플릿의 내용과 사용 목적에 대해 의견을 제시하지 않습니다. 특정 디렉토리에만 있으면 됩니다.

## 템플릿 정의 {#defining-a-template}

템플릿을 정의하려면, `tuist edit`를 수행하고 `Tuist/Templates` 아래에 템플릿을 나타내는 `name_of_template` 디렉토리를 생성합니다. 템플릿은 템플릿을 설명하는 `name_of_template.swift` 매니페스트 파일이 필요합니다. 따라서 `framework`라는 템플릿을 생성한다면, `Tuist/Templates` 아래에 `framework` 디렉토리를 생성하고 다음 내용을 가지는 `framework.swift` 매니페스트 파일을 생성해야 합니다:

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

템플릿을 정의한 후에, `scaffold` 명령어를 사용할 수 있습니다:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE]\
> 플랫폼은 옵셔널 인수이므로, `--platform macos` 인수없이 명령어 호출도 가능합니다.

`.string`과 `.files`가 유연성을 제공하지 않으면, `.file` 케이스를 통해 [Stencil](https://stencil.fuller.li/en/latest/) 템플릿 언어를 활용할 수 있습니다. 그 외에 여기에 정의된 필터를 추가적으로 사용할 수도 있습니다.

문자열 보간을 사용하면, 위에 `\(nameAttribute)`은 `{{ name }}`로 변환됩니다. 템플릿 정의에서 Stencil 필터를 사용하고 싶으면, 해당 보간을 수동으로 사용하고 원하는 필터를 추가할 수 있습니다. 예를 들어, 이름 속성을 소문자로 하려면 `\(nameAttribute)` 대신에 `{ { name | lowercase } }`을 사용하면 됩니다.

`.directory`를 사용하면, 주어진 경로에 전체 폴더를 복사할 수 있습니다.

> [!TIP] 프로젝트 설명 도우미
> 템플릿은 템플릿간의 코드 재사용을 위해 <LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명 도우미</LocalizedLink>의 사용을 지원합니다.
