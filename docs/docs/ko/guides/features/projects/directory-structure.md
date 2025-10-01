---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# 디렉토리 구조 {#디렉토리 구조}

Tuist 프로젝트는 일반적으로 Xcode 프로젝트를 대체하는 데 사용되지만, 이 사용 사례에만 국한되지는 않습니다. Tuist 프로젝트는
SPM 패키지, 템플릿, 플러그인 및 작업과 같은 다른 유형의 프로젝트를 생성하는 데에도 사용됩니다. 이 문서에서는 Tuist 프로젝트의 구조와
구성 방법에 대해 설명합니다. 이후 섹션에서는 템플릿, 플러그인 및 작업을 정의하는 방법을 다루겠습니다.

## 표준 튜이스트 프로젝트 {#표준-튜이스트-프로젝트}

튜이스트 프로젝트는 **튜이스트에서 생성되는 가장 일반적인 유형의 프로젝트입니다.** 앱, 프레임워크, 라이브러리 등을 구축하는 데 사용됩니다.
Xcode 프로젝트와 달리 Tuist 프로젝트는 Swift로 정의되므로 더 유연하고 유지 관리가 쉽습니다. 또한 Tuist 프로젝트는 선언적이기
때문에 이해하고 추론하기가 더 쉽습니다. 다음 구조는 Xcode 프로젝트를 생성하는 일반적인 Tuist 프로젝트의 구조를 보여줍니다:

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

- **Tuist 디렉토리:** 이 디렉터리에는 두 가지 용도가 있습니다. 첫째, 프로젝트의 루트가** 인 경우 **에 신호를 보냅니다. 이를
  통해 프로젝트의 루트를 기준으로 경로를 구성하고 프로젝트 내의 모든 디렉토리에서 Tuist 명령을 실행할 수 있습니다. 둘째, 다음 파일을
  위한 컨테이너입니다:
  - **프로젝트 설명 헬퍼:** 이 디렉터리에는 모든 매니페스트 파일에서 공유되는 Swift 코드가 포함되어 있습니다. 매니페스트 파일은
    `import ProjectDescriptionHelpers` 이 디렉터리에 정의된 코드를 사용할 수 있습니다. 코드 공유는 중복을
    피하고 프로젝트 전반의 일관성을 유지하는 데 유용합니다.
  - **Package.swift:** 이 파일에는 구성 및 최적화가 가능한 Xcode 프로젝트 및
    대상([CocoaPods](https://cococapods) 등)을 사용하여 통합하기 위한 Swift 패키지 종속성이 포함되어
    있습니다. 자세히
    <LocalizedLink href="/guides/features/projects/dependencies">여기</LocalizedLink>에서
    알아보세요.

- **루트 디렉토리**: 프로젝트의 루트 디렉터리로 `Tuist` 디렉터리가 포함되어 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    이 파일에는 모든 프로젝트, 작업 공간 및 환경에서 공유되는 Tuist에 대한 구성이 포함되어 있습니다. 예를 들어 스키마 자동 생성을
    비활성화하거나 프로젝트의 배포 대상을 정의하는 데 사용할 수 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    이 매니페스트는 Xcode 작업 공간을 나타냅니다. 다른 프로젝트를 그룹화하는 데 사용되며 파일과 스키마를 추가할 수도 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    이 매니페스트는 Xcode 프로젝트를 나타냅니다. 프로젝트의 일부인 대상과 그 종속성을 정의하는 데 사용됩니다.

위 프로젝트와 상호작용할 때 명령은 작업 디렉토리 또는 `--path` 플래그를 통해 지정된 디렉토리에서 `Workspace.swift` 또는
`Project.swift` 파일을 찾을 것으로 예상합니다. 매니페스트는 프로젝트의 루트를 나타내는 `Tuist` 디렉터리가 포함된 디렉터리
또는 디렉터리의 하위 디렉터리에 있어야 합니다.

> [!팁] Xcode 작업 공간을 사용하면 병합 충돌 가능성을 줄이기 위해 프로젝트를 여러 Xcode 프로젝트로 분할할 수 있습니다. 이러한
> 용도로 작업 공간을 사용했다면 Tuist에서는 작업 공간이 필요하지 않습니다. Tuist는 프로젝트와 그 종속 요소의 프로젝트를 포함하는
> 작업 공간을 자동으로 생성합니다.

## Swift 패키지 <Badge type="warning" text="beta" /> {#swift-package-badge-type-warning-textbeta-}

튜이스트는 SPM 패키지 프로젝트도 지원합니다. SPM 패키지로 작업하는 경우 아무것도 업데이트할 필요가 없습니다. 튜이스트는 자동으로
`Package.swift` 루트를 선택하며, 튜이스트의 모든 기능은 `Project.swift` 매니페스트처럼 작동합니다.

시작하려면 SPM 패키지에서 `tuist install` 및 `tuist generate` 을 실행하세요. 이제 프로젝트에 바닐라 Xcode
SPM 통합에서 볼 수 있는 것과 동일한 스키마와 파일이 모두 있어야 합니다. 그러나 이제
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>를 실행하고
대부분의 SPM 종속 요소와 모듈을 미리 컴파일할 수 있으므로 후속 빌드가 매우 빨라집니다.
