---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Develop · Guides · Tuist",
  "description": "Tuist 프로젝트의 구조와 이를 구성하는 방법에 대해 배워봅니다."
}
---
# Directory structure {#directory-structure}

Tuist 프로젝트는 일반적으로 Xcode 프로젝트를 대체하는데 사용하지만 이 용도로만 제한하지 않습니다. Tuist 프로젝트는 SPM 패키지, 템플릿, 플러그인, 그리고 작업과 같은 다른 종류의 프로젝트를 생성하는데 사용되기도 합니다. 이 문서에서는 Tuist 프로젝트의 구조와 이를 구성하는 방법에 대해 설명합니다. 다음 섹션에서는 템플릿, 플러그인, 그리고 작업을 정의하는 방법을 살펴봅니다.

## 표준 Tuist 프로젝트 {#standard-tuist-projects}

Tuist 프로젝트는 **Tuist로 생성하는 가장 일반적인 프로젝트 입니다.** 이 프로젝트는 앱, 프레임워크, 그리고 라이브러리 등을 빌드하는데 사용됩니다. Xcode 프로젝트와 달리, Tuist 프로젝트는 더 유연하고 유지하기 쉬운 Swift로 정의되어 있습니다. Tuist 프로젝트는 이해하고 추론하기 쉽게 더 선언적입니다. 다음 구조는 Xcode 프로젝트를 생성하는 일반적인 Tuist 프로젝트를 보여줍니다.

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

- **Tuist 디렉토리:** 이 디렉토리에는 두 가지 목적이 있습니다. 먼저, **프로젝트의 루트**를 나타냅니다. This allows constructing paths relative to the root of the project, and also running Tuist commands from any directory within the project. 두 번째로, 다음 파일을 포함하는 컨테이너 입니다:
  - **ProjectDescriptionHelpers:** 이 디렉토리는 모든 매니페스트 파일에서 공유되는 Swift 코드를 포함합니다. 매니페스트 파일은 이 디렉토리에 정의된 코드를 사용하기 위해 `import ProjectDescriptionHelpers`을 사용할 수 있습니다. 코드 공유는 프로젝트 전체의 중복을 피하고 일관성을 유지하는데 유용합니다.
  - **Package.swift:** 이 파일은 Tuist가 구성 가능하고 최적화할 수 있는 Xcode 프로젝트와 타겟 (예: [CocoaPods](https://cococapods)) 을 사용하여 통합하기 위한 Swift Package 의존성을 포함합니다. <LocalizedLink href="/guides/features/projects/dependencies">여기</LocalizedLink>서 더 알아봅니다.

- **루트 디렉토리**: `Tuist` 디렉토리도 포함하는 프로젝트의 루트 디렉토리 입니다.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Tuist.swift:</bold></LocalizedLink> 이 파일은 모든 프로젝트, 워크스페이스, 그리고 환경에 공유되는 Tuist에 대한 구성을 포함합니다. 예를 들어, 스킴의 자동 생성을 비활성화 하거나, 프로젝트의 배포 타겟을 정의할 수 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink> 이 매니페스트는 Xcode 워크스페이스를 나타냅니다. 다른 프로젝트를 그룹화 하고 파일과 스킴을 추가할 수도 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink> 이 매니페스트는 Xcode 프로젝트를 나타냅니다. 프로젝트의 타겟과 의존성을 정의합니다.

위 프로젝트와 상호작용할 때 명령어는 작업 디렉토리나 `--path` 플래그로 나타낸 디렉토리에 `Workspace.swift` 또는 `Project.swift` 파일을 찾습니다. 이 매니페스트는 프로젝트의 루트 인 `Tuist` 디렉토리를 포함하는 디렉토리나 하위 디렉토리에 위치해야 합니다.

> [!TIP]
> Xcode 워크스페이스는 병합 충돌을 줄이기 위해 Xcode 프로젝트를 여러개로 나눌 수 있습니다. 이러한 목적이 워크스페이스를 사용하는 목적이라면, Tuist에서는 워크스페이스를 사용할 필요가 없습니다. Tuist는 프로젝트와 의존성을 가진 프로젝트를 포함해 워크스페이스를 자동으로 생성합니다.

## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist는 SPM 패키지 프로젝트도 지원합니다. SPM 패키지를 작업하고 있다면 아무런 업데이트가 필요하지 않습니다. Tuist는 자동으로 루트 `Package.swift`를 선택하고 Tuist의 모든 기능은 `Project.swift` 매니페스트인 것처럼 동작합니다.

시작하려면, SPM 패키지에서 `tuist install`과 `tuist generate`를 수행합니다. 이제 프로젝트는 Xcode SPM에서 볼 수 있는 동일한 스킴과 파일을 가져야 합니다. 이제 <LocalizedLink href="/guides/features/build/cache">`tuist cache`</LocalizedLink>도 수행할 수 있으며 대부분의 SPM 의존성과 모듈을 미리 컴파일 되어 후속 빌드가 매우 빠르게 진행됩니다.
