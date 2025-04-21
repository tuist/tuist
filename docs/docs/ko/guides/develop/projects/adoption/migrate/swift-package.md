---
title: Migrate a Swift Package
titleTemplate: :title · Migrate · Adoption · Projects · Develop · Guides · Tuist
description: 프로젝트를 관리하는 Swift Package Manager를 Tuist 프로젝트로 마이그레이션 하는 방법을 알아봅니다.
---

# Migrate a Swift Package {#migrate-a-swift-package}

Swift Package Manager는 원래 Swift 코드의 의존성을 관리하기 위해 등장했지만, 결과적으로 프로젝트 전체를 관리하고 Objective-C 같은 다른 프로그래밍 언어를 지원하는 문제까지 해결하게 되었습니다. 이 도구는 원래 다른 목적으로 설계되었기 때문에, 대규모 프로젝트를 관리하기 데에는 Tuist가 제공할수 있는 유연성이나 성능 측면에서 부족함이 있었습니다. 이것은 [Bumble의 iOS 확장](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) 이라는 글에서 잘 설명되어 있으며, 해당 글에는 Swift Package Manager와 순수 Xcode 프로젝트간의 성능을 비교한 다음과 같은 표도 포함되어 있습니다.

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

우리는 종종 Swift Package Manager도 유사한 프로젝트 관리 역할을 수행할 수 있다는 이유로 Tuist의 필요성에 의문을 제기하는 개발자와 조직을 마주하고는 합니다. 일부 개발자들은 Swift Package Manager을 이용한 마이그레이션을 시도하지만, 결국 개발자 경험이 크게 저하되었다는 사실을 깨닫게 됩니다. 예를 들어, 파일의 이름을 변경하면 다시 인덱싱하기 위해 15초나 걸리는 경우도 있습니다. 무려 15초요!

**Apple이 Swift Package Manager를 대규모 프로젝트에 적합한 프로젝트 관리 도구로 발전시킬지는 여전히 불확실합니다.** 하지만, 현재로서는 그런 방향으로 나아간다는 뚜렷한 조짐은 보이지 않습니다. 사실 우리는 그와는 정반대의 흐름을 보고 있습니다. Apple은 Xcode에서 영감을 받아, 암시적 구성을 통해 편리함을 추구하는 방향으로 움직이고 있습니다. 하지만 이는 <LocalizedLink href="/guides/develop/projects/cost-of-convenience">여러분도 아시다시피</LocalizedLink> 규모가 커질수록 복잡성을 초래하는 주된 원인입니다. 우리는 Apple이 근본적인 원칙으로 되돌아가, 의존성 관리자로서는 타당했지만 프로젝트 관리자로서는 적절하지 않은 결정들, 예를 들어 컴파일된 언어를 프로젝트 정의의 인터페이스로 사용하는 방식 등을 재검토할 필요가 있다고 보고 있습니다.

> [!TIP] SPM은 의존성 관리도구로만 활용하자 \
> Tuist는 Swift Package Manager를 의존성 관리 도구로만 취급하며, 이런 용도로는 아주 훌륭합니다. 우리는 SPM을 의존성 해결 및 빌드를 위해서만 사용합니다. 프로젝트 정의를 위해서는 사용하지 않습니다.

## Swift Package Manager에서 Tuist로 마이그레이션 {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager와 Tuist는 유사한 점이 많기 때문에, 마이그레이션 과정은 간단합니다. 주요 차이점은 `Package.swift` 대신 Tuist의 DSL을 사용하여 프로젝트를 정의한다는 점입니다.

먼저, `Package.swift` 파일과 같은 위치에 `Project.swift` 파일을 생성하세요. 다음은 단일 타겟을 가진 프로젝트를 정의한 `Project.swift` 파일의 예시입니다, 다음은 단일 타겟을 가진 프로젝트를 정의한 `Project.swift` 파일의 예시입니다, 다음은 단일 타겟을 가진 프로젝트를 정의한 `Project.swift` 파일의 예시입니다.

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

몇 가지 주목 할 사항:

- **ProjectDescription**: `PackageDescription` 대신에 `ProjectDescription`을 사용합니다.
- **Project:** `package` 인스턴스를 내보내는 대신에 `project` 인스턴스를 내보냅니다.
- **Xcode 언어:** 프로젝트를 정의하는데 사용하는 기본 요소는 Xcode의 언어를 따르므로 스킴, 타겟, 그리고 Build Phases 등을 찾을 수 있습니다.

그 다음에 아래와 같은 내용을 담은 `Tuist.swift` 파일을 생성하세요.

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` 파일은 프로젝트의 구성 정보를 담고 있으며, 이 파일의 위치는 프로젝트 루트를 판단하는 기준이 됩니다. Tuist 프로젝트의 구조에 대해 더 알고 싶다면 <LocalizedLink href="/guides/develop/projects/directory-structure">디렉토리 구조</LocalizedLink> 문서를 참고하세요.

## 프로젝트 편집하기 {#editing-the-project}

이 명령어는 Xcode 프로젝트를 생성하며, 이를 열어 바로 작업을 시작할 수 있게 합니다. <LocalizedLink href="/guides/develop/projects/editing">`tuist edit`</LocalizedLink> 명령어를 사용하면 Xcode에서 프로젝트를 편집할 수 있습니다.

```bash
tuist edit
```

프로젝트 규모에 따라, 한 번에 전체를 마이그레이션 할 수도 있고 점진적으로 진행할 수도 있습니다. 먼저 작은 프로젝트를 통해 DSL과 작업흐름에 익숙해지는 것을 권장합니다. 항상 가장 많은 의존성을 가진 타겟부터 시작해서 최상위 타겟까지 순차적으로 전환하는 방식이 바람직합니다.
