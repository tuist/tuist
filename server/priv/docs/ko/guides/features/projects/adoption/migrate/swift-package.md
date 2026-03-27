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
<LocalizedLink href="/guides/features/projects/cost-of-convenience">이것은 알고 있듯이</LocalizedLink> 대규모에서 복잡성을 초래합니다. 우리는 Apple이 근본적인 원칙으로 돌아가서 의존성 관리 도구로 적합하지만
프로젝트 정의를 위해 컴파일된 언어를 인터페이스로 사용하는 방식과 같이 프로젝트 관리 도구로는 적합하지 않은 결정을 다시 검토해야 한다고
생각합니다.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist는 Swift Package Manager를 의존성 관리 도구로 취급하고 이는 매우 훌륭합니다. 우리는 Swift Package
Manager를 의존성을 분석하고 빌드하는데 사용합니다. 우리는 Swift Package Manager가 프로젝트 정의를 위해 설계되지
않았으므로 이 목적으로 사용하지 않습니다.
<!-- -->
:::

## Swift Package Manager에서 Tuist로 마이그레이션 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager와 Tuist는 많이 유사하므로 마이그레이션 과정이 단순합니다. 주요 차이점은 프로젝트를 정의하는데
`Package.swift` 대신에 Tuist의 DSL을 사용해 정의합니다.

먼저 `Project.swift` 파일을 생성하고 다음으로 `Package.swift` 파일을 생성합니다. `Project.swift` 파일은
프로젝트 정의를 포함합니다. 다음은 단일 타겟을 가지는 프로젝트를 정의하는 `Project.swift` 파일의 예제입니다:

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

참고할 사항:

- **ProjectDescription**: `PackageDescription` 대신에 `ProjectDescription`을 사용합니다.
- **Project:** `package` 인스턴스를 내보내는 대신에 `project` 인스턴스를 내보냅니다.
- **Xcode 용어:** 프로젝트 정의하는데 사용하는 기본 요소는 Xcode의 용어를 따르므로 scheme, target, build
  phase 등을 사용할 수 있습니다.

그런 다음에 다음 내용을 포함하는 `Tuist.swift` 파일을 생성합니다:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`는 프로젝트의 설정을 포함하고 이 파일의 경로가 프로젝트의 루트를 결정하는 기준이 됩니다. Tuist 프로젝트의 구조에
대해 더 자세히 알아보려면
<LocalizedLink href="/guides/features/projects/directory-structure">디렉토리 구조</LocalizedLink> 문서를 확인하기 바랍니다.

## 프로젝트 편집 {#editing-the-project}

Xcode에서 프로젝트를 편집하기 위해
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>를 사용할 수 있습니다. 이 명령어는 프로젝트를 열고 작업할 수 있는 Xcode 프로젝트를 생성합니다.

```bash
tuist edit
```

프로젝트 규모에 따라 한 번에 적용하거나 점진적으로 적용할지 고려할 수 있습니다. 우리는 DSL과 워크플로에 익숙해지기 위해 작은 프로젝트부터
시작하는 것을 권장합니다. 저희의 조언은 항상 가장 많이 의존되는 타겟부터 시작해 최상위 타겟까지 점차적으로 작업해 나가길 권장합니다.
