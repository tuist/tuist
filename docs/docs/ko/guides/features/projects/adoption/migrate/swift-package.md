---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Swift Package 마이그레이션 {#migrate-a-swift-package}

Swift Package Manager는 원래 Swift 코드 의존성을 관리하기 위해 등장했지만, 의도치 않게 프로젝트 관리와
Objective-C와 같은 다른 프로그래밍 언어 지원 문제까지 해결하게 되었습니다. 이 도구는 이런 목적으로 설계된 것이 아니기 때문에 대규모
프로젝트를 관리할 때 Tuist가 제공하는 유연성, 성능, 강력함이 부족해 사용하기 어려울 수 있습니다. 이러한 내용은 [Scaling iOS
at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 글에
잘 설명되어 있으며, 여기서는 Swift Package Manager와 Xcode 프로젝트의 성능을 비교한 다음의 표도 포함하고 있습니다:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

우리는 Swift Package Manager로 프로젝트 관리할 수 있다는 이유로 Tuist에 의문을 제기하는 개발자나 조직을 마주치곤 합니다.
일부는 마이그레이션을 시도하다가 개발자 경험이 크게 저하되는 것을 뒤늦게 깨닫습니다. 예를 들어 파일 이름을 변경하는데 최대 15초가 걸릴 수
있습니다. 15초!

**Apple이 Swift Package Manager를 대규모 프로젝트 관리 도구로 발전시킬지는 확실하지 않습니다.** 그러나 아직까지는 그런
징후가 보이지 않습니다. 오히려 반대 방향으로 가고 있습니다. Apple은 Xcode에서 영감을 받은 결정(예를 들어 암묵적 설정을 통한 편의성
추구)을 선택하고 있는데
<LocalizedLink href="/guides/features/projects/cost-of-convenience">이것은 알고
있듯이</LocalizedLink> 대규모에서 복잡성을 초래합니다. 우리는 Apple이 근본적인 원칙으로 돌아가서 의존성 관리 도구로 적합하지만
프로젝트 정의를 위해 컴파일된 언어를 인터페이스로 사용하는 방식과 같이 프로젝트 관리 도구로는 적합하지 않은 결정을 다시 검토해야 한다고
생각합니다.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist는 Swift Package Manager를 의존성 관리
<!-- -->
:::

## Migrating from Swift Package Manager to Tuist {#migrating-from-swift-package-manager-to-tuist}

The similarities between Swift Package Manager and Tuist make the migration
process straightforward. The main difference is that you'll be defining your
projects using Tuist's DSL instead of `Package.swift`.

First, create a `Project.swift` file next to your `Package.swift` file. The
`Project.swift` file will contain the definition of your project. Here's an
example of a `Project.swift` file that defines a project with a single target:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Some things to note:

- **ProjectDescription**: Instead of using `PackageDescription`, you'll be using
  `ProjectDescription`.
- **Project:** Instead of exporting a `package` instance, you'll be exporting a
  `project` instance.
- **Xcode language:** The primitives that you use to define your project mimic
  Xcode's language, so you'll find schemes, targets, and build phases among
  others.

Then create a `Tuist.swift` file with the following content:

```swift
import ProjectDescription

let tuist = Tuist()
```

The `Tuist.swift` contains the configuration for your project and its path
serves as a reference to determine the root of your project. You can check out
the
<LocalizedLink href="/guides/features/projects/directory-structure">directory
structure</LocalizedLink> document to learn more about the structure of Tuist
projects.

## Editing the project {#editing-the-project}

You can use <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> to edit the project in Xcode. The command will generate an
Xcode project that you can open and start working on.

```bash
tuist edit
```

Depending on the size of the project, you might consider using it in one shot or
incrementally. We recommend starting with a small project to get familiar with
the DSL and the workflow. Our advise is always to start from the most depended
upon target and work all the way up to the top-level target.
