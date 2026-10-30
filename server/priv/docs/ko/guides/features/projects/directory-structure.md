---
{
  "title": "디렉터리 구조",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 프로젝트의 구조와 조직화 방법을 알아봅니다."
}
---
# 디렉터리 구조 {#directory-structure}

Tuist 프로젝트는 일반적으로 Xcode 프로젝트를 대체하는 데 사용되지만, 이 용도에만 제한되지 않습니다. Tuist 프로젝트는 SPM 패키지, 템플릿, 플러그인 및 작업과 같은 다른 유형의 프로젝트를 생성하는 데에도 사용됩니다. 이 문서에서는 Tuist 프로젝트의 구조와 이를 구성하는 방법을 설명합니다. 이후 섹션에서는 템플릿, 플러그인 및 작업을 정의하는 방법을 다룹니다.

## 표준 Tuist 프로젝트 {#standard-tuist-projects}

Tuist 프로젝트는 **Tuist가 생성하는 가장 일반적인 프로젝트 유형입니다.** 앱, 프레임워크 및 라이브러리 등을 빌드하는 데 사용됩니다. Xcode 프로젝트와 달리 Tuist 프로젝트는 Swift로 정의되어 더 유연하고 유지 관리가 쉽습니다. 또한 Tuist 프로젝트는 선언적이어서 이해하고 추론하기가 더 쉽습니다. 다음 구조는 Xcode 프로젝트를 생성하는 일반적인 Tuist 프로젝트를 보여줍니다.

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Tuist 디렉터리:** 이 디렉터리는 두 가지 목적이 있습니다. 첫째, **프로젝트 루트의 위치**를 나타냅니다. 이를 통해 프로젝트 루트에 상대적인 경로를 구성할 수 있으며, 프로젝트 내 모든 디렉터리에서 Tuist 명령을 실행할 수 있습니다. 둘째, 다음 파일들을 포함하는 컨테이너 역할을 합니다.
  - **ProjectDescriptionHelpers:** 이 디렉터리에는 모든 매니페스트 파일에서 공유되는 Swift 코드가 포함되어 있습니다. 매니페스트 파일은 `import ProjectDescriptionHelpers`하여 이 디렉터리에 정의된 코드를 사용할 수 있습니다. 코드를 공유하면 중복을 피하고 프로젝트 간 일관성을 보장하는 데 유용합니다.
  - **Package.swift:** 이 파일에는 Tuist가 구성 가능하고 최적화 가능한 Xcode 프로젝트 및 타겟(예: [CocoaPods](https://cococapods))을 사용하여 통합할 Swift Package 종속성이 포함되어 있습니다. 자세한 내용은 <.localized_link href="/guides/features/projects/dependencies">여기</.localized_link>를 참조하세요.

- **루트 디렉터리**: `Tuist` 디렉터리도 포함하는 프로젝트의 루트 디렉터리입니다.
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></.localized_link> 이 파일에는 모든 프로젝트, 워크스페이스 및 환경에서 공유되는 Tuist 구성이 포함되어 있습니다. 예를 들어, 스킴의 자동 생성을 비활성화하거나 프로젝트의 배포 대상을 정의하는 데 사용할 수 있습니다.
  - <.localized_link href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></.localized_link> 이 매니페스트는 Xcode 워크스페이스를 나타냅니다. 다른 프로젝트를 그룹화하는 데 사용되며 추가 파일과 스킴을 추가할 수도 있습니다.
  - <.localized_link href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></.localized_link> 이 매니페스트는 Xcode 프로젝트를 나타냅니다. 프로젝트에 속하는 타겟과 해당 종속성을 정의하는 데 사용됩니다.

위의 프로젝트와 상호 작용할 때, 명령은 작업 디렉터리 또는 `--path` 플래그로 지정된 디렉터리에서 `Workspace.swift` 또는 `Project.swift` 파일을 찾기를 기대합니다. 매니페스트는 프로젝트 루트를 나타내는 `Tuist` 디렉터리를 포함하는 디렉터리나 그 하위 디렉터리에 있어야 합니다.

> [!TIP]
> Xcode 워크스페이스는 병합 충돌 가능성을 줄이기 위해 프로젝트를 여러 Xcode 프로젝트로 분할할 수 있게 해줍니다. 만약 워크스페이스를 그런 목적으로 사용했다면, Tuist에서는 필요하지 않습니다. Tuist는 프로젝트와 해당 종속성 프로젝트를 포함하는 워크스페이스를 자동으로 생성합니다.


## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist는 SPM 패키지 프로젝트도 지원합니다. SPM 패키지에서 작업 중이라면 아무것도 업데이트할 필요가 없습니다. Tuist는 루트 `Package.swift`를 자동으로 인식하며, Tuist의 모든 기능은 마치 `Project.swift` 매니페스트인 것처럼 작동합니다.

시작하려면 SPM 패키지에서 `tuist install` 및 `tuist generate`를 실행하세요. 이제 프로젝트에는 기본 Xcode SPM 통합에서 볼 수 있는 것과 동일한 모든 스킴과 파일이 있어야 합니다. 그러나 이제 <.localized_link href="/guides/features/cache">`tuist cache`</.localized_link>를 실행하여 대부분의 SPM 종속성과 모듈을 사전 컴파일할 수 있으므로 후속 빌드가 매우 빨라집니다.
