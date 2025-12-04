---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifests {#manifests}

Tuist는 프로젝트와 워크스페이스를 선언하고 생성 프로세스를 환경 설정하는 주요 방법으로써 Swift 파일들을 기본으로 합니다. 이 파일들은
These 문서를 통해 **manifest 파일** 로 참조 됩니다.

Swift를 사용하는 것에 대한 결정은 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/)가 패키지를 정의하기 위해
Swift 파일들을 사용하는 것에서 영감을 받았습니다고맙게도 Swift를 사용해서 우리는 컴파일러를 실행할 수 있었는데 여러 다른
Manifest 파일들에 전체적으로 내용의 정확성과 코드 재사용을, 문법 강조, 자동완성, 유효성 검증 등 최고의 편집 경험을 제공하기 위해
Xcode를 문법을 강조하고 사용할 수 있게 되었습니다.

::: info 캐싱
<!-- -->
Manifest 파일들이 컴파일이 되어야 하는 Swift 파일들이기 때문에, Tuist는 파싱 속도를 높이기 위해 컴파일 결과를 캐시 합니다.
그러므로, 여러분은 Tuist를 처음 실행하면 프로젝트를 다시 만들지 않고 다음에는 더 빨라 진다는 것을 알 겁니다.
<!-- -->
:::

## Project.swift {#projectswift}

The
<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
manifest declares an Xcode project. The project gets generated in the same
directory where the manifest file is located with the name indicated in the
`name` property.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
The only variable that should be at the root of the manifest is `let project =
Project(...)`. If you need to reuse code across various parts of the manifest,
you can use Swift functions.
<!-- -->
:::

## Workspace.swift {#workspaceswift}

By default, Tuist generates an [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
containing the project being generated and the projects of its dependencies. If
for any reason you'd like to customize the workspace to add additional projects
or include files and groups, you can do so by defining a
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
manifest.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

::: info Mise란?
<!-- -->
Tuist will resolve the dependency graph and include the projects of the
dependencies in the workspace. You don't need to include them manually. This is
necessary for the build system to resolve the dependencies correctly.
<!-- -->
:::

### Multi or mono-project {#multi-or-monoproject}

A question that often comes up is whether to use a single project or multiple
projects in a workspace. In a world without Tuist where a mono-project setup
would lead to frequent Git conflicts the usage of workspaces is encouraged.
However, since we don't recommend including the Tuist-generated Xcode projects
in the Git repository, Git conflicts are not an issue. Therefore, the decision
of using a single project or multiple projects in a workspace is up to you.

In the Tuist project we lean on mono-projects because the cold generation time
is faster (fewer manifest files to compile) and we leverage
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink> as a unit of encapsulation. However, you might want to
use Xcode projects as a unit of encapsulation to represent different domains of
your application, which aligns more closely with the Xcode's recommended project
structure.

## Tuist.swift {#tuistswift}

Tuist provides
<LocalizedLink href="/contributors/principles.html#default-to-conventions">sensible
defaults</LocalizedLink> to simplify project configuration. However, you can
customize the configuration by defining a
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
at the root of the project, which is used by Tuist to determine the root of the
project.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
