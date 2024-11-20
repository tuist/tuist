---
title: Code sharing
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: manifest 파일 간의 코드 공유를 통해 중복을 줄이고 일관성을 유지하는 방법을 알아보세요
---

# Code sharing {#code-sharing}

Xcode를 대규모 프로젝트에서 사용할 때의 한계점 중 하나는 `.xcconfig` 파일을 통한 빌드 설정 외에는 프로젝트의 다른 요소들을 재사용할 수 없다는 점입니다. 프로젝트 정의를 재사용할 수 있으면 다음과 같은 장점이 있습니다:

- 변경 사항을 한 곳에서 적용하면 모든 프로젝트에 자동으로 반영되므로 **유지보수**가 수월해집니다.
- 새로운 프로젝트들이 따를 수 있는 규칙을 정의할 수 있습니다.
- Projects are more **consistent** and therefore the likelihood of broken builds due inconsistencies is significantly less.
- Adding a new projects becomes an easy task because we can reuse the existing logic.

Reusing code across manifest files is possible in Tuist thanks to the concept of **project description helpers**.

> [!TIP] A TUIST UNIQUE ASSET
> Many organizations like Tuist because they see in project description helpers a platform for platform teams to codify their own conventions and come up with their own language for describing their projects. For example, YAML-based project generators have to come up with their own YAML-based propietary templating solution, or force organizations onto building their tools upon.

## Project description helpers {#project-description-helpers}

Project description helpers are Swift files that get compiled into a module, `ProjectDescriptionHelpers`, that manifest files can import. The module is compiled by gathering all the files in the `Tuist/ProjectDescriptionHelpers` directory.

You can import them into your manifest file by adding an import statement at the top of the file:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` are available in the following manifests:

- `Project.swift`
- `Package.swift` (only behind the `#TUIST` compiler flag)
- `Workspace.swift`

## Example {#example}

The snippets below contain an example of how we extend the `Project` model to add static constructors and how we use them from a `Project.swift` file:

::: code-group

```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "io.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "io.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```

:::

> [!TIP] A TOOL TO ESTABLISH CONVENTIONS
> Note how through the function we are defining conventions about the name of the targets, the bundle identifier, and the folders structure.
