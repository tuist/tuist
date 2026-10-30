---
{
  "title": "Swift 패키지 마이그레이션",
  "titleTemplate": ":title · 마이그레이션 · 도입 · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Swift Package Manager 프로젝트 관리에서 Tuist로 마이그레이션하세요."
}
---
# Swift 패키지 마이그레이션 {#migrate-a-swift-package}

Swift Package Manager는 Swift 코드의 의존성 관리자로 등장했으며, 의도치 않게 프로젝트 관리와 Objective-C와 같은 다른 프로그래밍 언어 지원을 해결하는 역할을 맡게 되었습니다. 이 도구는 다른 목적을 위해 설계되었기 때문에 Tuist가 제공하는 유연성, 성능 및 강력함을 갖추지 못해 대규모 프로젝트 관리에는 적합하지 않습니다. 이러한 문제는 [Bumble의 iOS 확장 사례](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 아티클에서 잘 설명되어 있으며, 다음 표는 Swift Package Manager와 네이티브 Xcode 프로젝트의 성능을 비교합니다:

<img style="max-width: 400px;" alt="SPM과 네이티브 Xcode 프로젝트 사용 시 성능 저하를 비교한 표" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager가 유사한 프로젝트 관리 역할을 수행할 수 있다고 생각해 Tuist의 필요성에 의문을 제기하는 개발자와 조직을 종종 마주칩니다. 일부는 마이그레이션을 시도했다가 개발자 경험이 크게 저하되었다는 사실을 나중에 깨닫기도 합니다. 예를 들어, 파일 이름을 변경하면 재인덱싱에 최대 15초가 걸릴 수 있습니다. 무려 15초나!

**Apple이 Swift Package Manager를 대규모 프로젝트 관리용으로 만들지는 불확실합니다.** 그러나 현재로서는 그런 움직임이 보이지 않습니다. 오히려 그 반대 현상이 관찰됩니다. Apple은 암시적 구성을 통해 편의성을 추구하는 등 Xcode 중심의 결정을 내리고 있으며, <.localized_link href="/guides/features/projects/cost-of-convenience">알다시피</.localized_link> 이는 대규모 환경에서 복잡성의 원인이 됩니다. 저희는 Apple이 근본 원칙으로 돌아가 의존성 관리 도구로서는 합리적이었지만 프로젝트 관리 도구로서는 부적합했던 몇 가지 결정(예: 프로젝트를 정의하기 위한 인터페이스로 컴파일된 언어 사용)을 재검토해야 한다고 생각합니다.

> [!TIP]
> **단순히 의존성 관리자로만 사용하는 SPM**
>
> Tuist는 Swift Package Manager를 의존성 관리자로 취급하며, 이는 매우 훌륭한 도구입니다. 저희는 이를 의존성 해결과 빌드에 사용합니다. 하지만 프로젝트 정의 용도로는 설계되지 않았으므로 사용하지 않습니다.


## Swift Package Manager에서 Tuist로 마이그레이션 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager와 Tuist 간의 유사성 덕분에 마이그레이션 과정은 간단합니다. 주요 차이점은 `Package.swift` 대신 Tuist의 DSL을 사용하여 프로젝트를 정의한다는 점입니다.

먼저, `Package.swift` 파일 옆에 `Project.swift` 파일을 생성하세요. `Project.swift` 파일에는 프로젝트 정의가 포함됩니다. 다음은 단일 타겟을 가진 프로젝트를 정의하는 `Project.swift` 파일의 예시입니다:

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

주의할 사항:

- **ProjectDescription**: `PackageDescription` 대신 `ProjectDescription`를 사용합니다.
- **프로젝트:** `package` 인스턴스를 export하는 대신 `project` 인스턴스를 export합니다.
- **Xcode 언어:** 프로젝트 정의에 사용하는 기본 요소는 Xcode의 언어 구조를 모방하므로 스킴, 타겟, 빌드 단계 등을 찾을 수 있습니다.

그런 다음 다음 내용을 포함하는 `Tuist.swift` 파일을 생성하세요:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`에는 프로젝트 구성이 포함되며, 해당 경로는 프로젝트 루트를 결정하는 참조점으로 사용됩니다. Tuist 프로젝트 구조에 대해 자세히 알아보려면 <.localized_link href="/guides/features/projects/directory-structure">디렉터리 구조</.localized_link> 문서를 확인하세요.

## 프로젝트 편집 {#editing-the-project}

<.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link>를 사용하여 Xcode에서 프로젝트를 편집할 수 있습니다. 이 명령은 열어서 작업을 시작할 수 있는 Xcode 프로젝트를 생성합니다.

```bash
tuist edit
```

프로젝트 크기에 따라 한 번에 실행하거나 점진적으로 적용하는 방법을 고려할 수 있습니다. DSL과 워크플로우에 익숙해지기 위해 작은 프로젝트부터 시작하는 것을 권장합니다. 가장 많이 의존되는 타겟부터 시작하여 최상위 타겟까지 진행하는 것이 좋습니다.
