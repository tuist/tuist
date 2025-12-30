---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# 디렉토리 구조 {#directory-structure}

Tuist 프로젝트들이 이전 프로젝트를 대체하는데 일반적으로 사용되지만, 그 경우에만 제한되지는 않습니다. Tuist 프로젝트들은 사용되기도
합니다 SPM 패키지, 템플릿, 플러그인, 태스크 등 다른 형식의 프로젝트를 생성하는데도 사용됩니다. 이 문서는 Tuist 프로젝트의 구조와
어떻게 구성되는 지를 설명 합니다. 다음 섹션에서는 어떻게 템플릿, 플러그인, 태스크를 정의하는지 다룰 것 입니다.

## 표준 Tuist 프로젝트 {#standard-tuist-projects}

Tuist 프로젝트들은 **Tuist에 생성된 가장 일반적인 형태의 프로젝트** 입니다. 다른데 있는 앱, 프레임워크와 라이브러리들을 만들기
위해도 사용됩니다. Xcode 프로젝트와는 달리, Tuist 프로젝트는 좀 더 동적이고 유지보수에 용이 하도록 Swift로 선언 됩니다.
Tuist 프로젝트들은 또한 더 이해하기 유추하기 쉽도록 좀 더 선언적 입니다. 아래 구조는 Xcode 프로젝트를 생성하는 기본적인 Tuist
프로젝트를 보여줍니다:

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
    방지하고 프로젝트 전반의 일관성을 유지하는 데 유용합니다.
  - **Package.swift:** 이 파일에는 구성 및 최적화가 가능한 Xcode 프로젝트 및
    대상([CocoaPods](https://cococapods) 등)을 사용하여 통합하기 위한 Swift 패키지 종속성이 포함되어
    있습니다. 자세히
    <LocalizedLink href="/guides/features/projects/dependencies">여기</LocalizedLink>에서
    알아보세요.

- **루트 디렉토리**: 프로젝트의 루트 디렉터리로 `Tuist` 디렉터리가 포함되어 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    이 파일은 모든 프로젝트, 워크스페이스, 환경 변수에 공유되는 Tuist의 환경 설정을 포함 합니다. 예를 들어, 자동 Scheme
    생성을 비활성화 하거나 배포 대상 OS Target을 정의하는데 사용될 수 있습니다.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    이 Manifest는 Xcode의 워크스페이스를 나타내는데 다른 프로젝트들을 그룹화하기 위해 사용하고 추가적인 파일이나 Scheme을
    추가하는데도 사용됩니다.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    이 Manifest는 Xcode 프로젝트를 나타내는데 프로젝트의 일부인 Target과 Target의 의존성들을 정의하기 위해 사용
    됩니다.

위의 프로젝트들과 상호작용 할 때, 명령어는 `Workspace.swift` 나 `Project.swift` 파일을 작업 디렉토리나
`--path`로 지정된 디렉토리에서 찾기를 기대합니다. Manifest는 최상위 프로젝트를 나타내는 `Tuist` 디렉토리를 가지고 있는
디렉토리나 하위 디렉토리에 있어야 합니다.

::: tip
<!-- -->
Xcode 워크스페이스는 병합 출동의 가능성을 줄이기 위해 프로젝트들을 여러 Xcode 프로젝트로 나눌 수 있습니다. 그게 우리가 워크스페이스를
사용하고 있던 이유라면, Tuist에서는 필요하지 않습니다 Tuist는 프로젝트와 의존하는 프로젝트들을 포함하는 워크스페이스를 자동으로 생성
합니다.
<!-- -->
:::

## Swift 패키지 <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist는 SPM 패키지 프로젝트들도 지원 합니다. SPM 패키지에서 작업하고 있다면 아무것도 업데이트할 필요가 없습니다. Tuist가
자동으로 최상위 `Package.swift`가 자동으로 가져가고 모든 Tuist 기능들은 `Project.swift` Manifest 처럼 동작
합니다.

시작하려면, SPM 패키지에서 `tuist install` 와 `tuist generate` 를 실행하세요. 프로젝트는 이제 순수 Xcode
SPM 통합에서 볼게 될 같은 Scheme과 File들을 가져야 합니다. 하지만, 이제 계속되는 빌드를 극도록 빠르게 만들기 위해
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>를 실행하고
SPM 의존성 대부분과 미리 컴파일 된 모듈들을 가질 수 있습니다.
