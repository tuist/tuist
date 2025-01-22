---
title: Migrate a Swift Package
titleTemplate: :title · Migrate · Adoption · Projects · Develop · Guides · Tuist
description: 프로젝트를 관리하는 Swift Package Manager를 Tuist 프로젝트로 마이그레이션 하는 방법을 알아봅니다.
---

# Migrate a Swift Package {#migrate-a-swift-package}

Swift Package Manager는 Swift 코드의 의존성 관리를 위해 등장했지만 의도치않게 프로젝트 관리 문제를 해결하고 Objective-C와 같은 다른 프로그래밍 언어를 지원하게 되었습니다. 이 툴은 다른 목적으로 설계되었지만, Tuist에서 제공하는 유연성, 성능, 그리고 기능이 부족해서 대규모 프로젝트에 적합하지 않을 수 있습니다. 이것은 [Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 문서에 잘 설명되어 있으며, 다음과 같이 Swift Package Manager와 Xcode 프로젝트의 성능 비교표를 포함합니다:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager가 프로젝트 관리 역할을 할 수 있다는 점을 고려하면 Tuist의 필요성에 대해 의문을 제기하는 개발자와 조직을 만나곤 합니다. 마이그레이션을 진행한 후에 일부 인원은 개발자의 경험이 크게 저하되어 있었다는 것을 깨닫습니다. 예를 들어, 파일의 이름을 바꾸면 다시 인덱싱하는데 15초가 걸릴 수 있습니다. 15초!

**Apple은 Swift Package Manager를 대규모 프로젝트에 적합하게 만들지는 알 수 없습니다.** 그러나 이런 일은 일어나지 않을 것 같습니다. 실제로, 우리는 그 반대의 상황을 보고 있습니다. Apple은 암시적 구성을 통해 편리함을 추구하는 것과 같이 Xcode에서 영감을 받아 결정 합니다. 이것은 <LocalizedLink href="/guides/develop/projects/cost-of-convenience">아시다시피</LocalizedLink> 대규모 프로젝트에서 복잡성의 원인입니다. 우리는 Apple이 기본 원칙으로 돌아가서 의존성 관리 도구로서 의미가 있지만 프로젝트 관리 도구로는 의미가 없는 몇 가지 결정을 재검증 해야 한다고 생각합니다. 예를 들어 프로젝트 정의하기 위한 인터페이스로 컴파일된 언어를 사용하는 것입니다.

> [!TIP] 의존성 관리 도구로의 SPM\
> Tuist는 Swift Package Manager를 의존성 관리 도구로만 취급하고, 의존성 관리 도구로는 아주 훌륭합니다. 우리는 의존성을 해결하고 빌드를 위해 사용합니다. 프로젝트를 정의하는 용도로 설계되지 않았으므로, 그 용도로 사용하지 않습니다.

## Swift Package Manager를 Tuist로 마이그레이션 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager와 Tuist는 유사하므로 마이그레이션 동작은 간단합니다. 다른점은 `Package.swift` 대신에 Tuist의 DSL을 사용하여 프로젝트를 정의한다는 것입니다.

먼저, `Package.swift` 파일 있는 곳에 `Project.swift` 파일을 생성합니다. `Project.swift` 파일은 프로젝트 정의가 포함됩니다. 다음은 하나의 타겟을 가지는 프로젝트를 정의하는 `Project.swift` 파일의 예제입니다:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

주의할 점:

- **ProjectDescription**: `PackageDescription` 대신에 `ProjectDescription`을 사용합니다.
- **Project:** `package` 인스턴스를 내보내는 대신에 `project` 인스턴스를 내보냅니다.
- **Xcode 언어:** 프로젝트를 정의하는데 사용하는 기본 요소는 Xcode의 언어를 따르므로 스킴, 타겟, 그리고 Build Phases 등을 찾을 수 있습니다.

그런 다음에 다음 내용을 가지는 `Tuist.swift` 파일을 생성합니다:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`는 프로젝트의 구성을 포함하고 해당 파일의 경로는 프로젝트의 루트를 결정하는 기준으로 사용됩니다. Tuist 프로젝트의 구조에 대해 알아보려면 <LocalizedLink href="/guides/develop/projects/directory-structure">디렉토리 구조</LocalizedLink> 문서에서 확인 가능합니다.

## 프로젝트 수정 {#editing-the-project}

Xcode에서 프로젝트를 수정하기 위해 <LocalizedLink href="/guides/develop/projects/editing">`tuist edit`</LocalizedLink>를 사용할 수 있습니다. 이 명령어는 Xcode 프로젝트를 생성하고 생성된 프로젝트를 열어 작업을 시작할 수 있게 합니다.

```bash
tuist edit
```

프로젝트 규모에 따라 한 번에 사용하거나 점진적으로 사용할 수 있습니다. DSL과 워크플로우에 익숙해지기 위해 작은 프로젝트로 시작하는 것을 권장합니다. 우리의 조언은 가장 많은 의존성을 가진 타겟부터 시작하여 최상위 타겟까지 차례대로 작업하라는 것입니다.
