---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Swift 패키지 마이그레이션 {#migrate-a-swift-package}

Swift 패키지 관리자는 의도치 않게 프로젝트 관리와 Objective-C와 같은 다른 프로그래밍 언어 지원이라는 문제를 해결하기 위해
Swift 코드의 종속성 관리자로 등장했습니다. 이 도구는 다른 목적을 염두에 두고 설계되었기 때문에 Tuist가 제공하는 유연성, 성능 및
기능이 부족하여 대규모 프로젝트를 관리하는 데 사용하기 어려울 수 있습니다. 이 점은 [범블에서 iOS
확장하기](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 문서에 잘
설명되어 있으며, 여기에는 Swift 패키지 관리자와 기본 Xcode 프로젝트의 성능을 비교한 다음 표가 포함되어 있습니다:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift 패키지 관리자가 비슷한 프로젝트 관리 역할을 할 수 있다고 생각하여 Tuist의 필요성에 이의를 제기하는 개발자와 조직을 종종 만나게
됩니다. 마이그레이션을 시도했다가 나중에 개발자 환경이 현저히 저하되었다는 사실을 깨닫는 경우도 있습니다. 예를 들어, 파일 이름을 변경하면
색인을 다시 생성하는 데 최대 15초가 걸릴 수 있습니다. 15초라고요!

**Apple이 Swift 패키지 관리자를 대규모 프로젝트 관리자로 만들지 여부는 불확실합니다.** 하지만 그렇게 될 조짐은 전혀 보이지
않습니다. 오히려 정반대의 현상이 나타나고 있습니다. 그들은 암시적 구성을 통해 편의성을 달성하는 등 Xcode에서 영감을 받은 결정을 내리고
있는데, <LocalizedLink href="/guides/features/projects/cost-of-convenience"> 아시다시피
</LocalizedLink> 이는 규모에 따른 복잡성의 원천입니다. 우리는 Apple이 첫 번째 원칙으로 돌아가 프로젝트 정의 인터페이스로
컴파일된 언어를 사용하는 것과 같이 의존성 관리자로서는 타당하지만 프로젝트 관리자로서는 타당하지 않은 일부 결정을 재검토해야 한다고 생각합니다.

> [!팁] 종속성 관리자로서의 SPM 튜이스트는 Swift 패키지 관리자를 종속성 관리자로 취급하며, 이는 매우 훌륭한 도구입니다. 우리는
> 종속성을 해결하고 빌드하는 데 사용합니다. 프로젝트를 정의하는 데는 사용하지 않는데, 그 용도로 설계되지 않았기 때문입니다.

## Swift 패키지 관리자에서 Tuist로 마이그레이션 {#migrating-from-swift-package-manager-to-tuist}

Swift 패키지 관리자와 Tuist의 유사점 덕분에 마이그레이션 프로세스가 간단합니다. 가장 큰 차이점은 `Package.swift` 대신
Tuist의 DSL을 사용하여 프로젝트를 정의한다는 것입니다.

먼저 `Package.swift` 파일 옆에 `Project.swift` 파일을 만듭니다. ` Project.swift` 파일에는 프로젝트의
정의가 포함됩니다. 다음은 단일 대상을 가진 프로젝트를 정의하는 `Project.swift` 파일의 예시입니다:

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

몇 가지 주의해야 할 사항:

- **ProjectDescription**: ` PackageDescription` 대신 `ProjectDescription` 을 사용하게
  됩니다.
- **프로젝트:** ` 패키지` 인스턴스를 내보내는 대신 `프로젝트` 인스턴스를 내보내게 됩니다.
- **Xcode 언어:** 프로젝트를 정의하는 데 사용하는 프리미티브는 Xcode의 언어를 모방하므로 스키마, 타겟, 빌드 단계 등을 찾을 수
  있습니다.

그런 다음 다음 콘텐츠로 `Tuist.swift` 파일을 만듭니다:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 에는 프로젝트의 구성이 포함되어 있으며, 이 경로는 프로젝트의 루트를 결정하는 데 참조가 됩니다. 1} 디렉터리
구조</LocalizedLink> 문서를 확인하여 Tuist 프로젝트의 구조에 대해 자세히 알아볼 수 있습니다.

## 프로젝트 편집하기 {#편집-프로젝트}

1}`tuist edit`</LocalizedLink>를 사용하여 Xcode에서 프로젝트를 편집할 수 있습니다. 이 명령은 열어서 작업을 시작할
수 있는 Xcode 프로젝트를 생성합니다.

```bash
tuist edit
```

프로젝트의 규모에 따라 한 번에 사용하거나 점진적으로 사용할 수 있습니다. 작은 프로젝트부터 시작하여 DSL과 워크플로에 익숙해지는 것이
좋습니다. 항상 가장 의존도가 높은 대상부터 시작하여 최상위 대상까지 작업하는 것이 좋습니다.
