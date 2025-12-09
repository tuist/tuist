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

- **Tuist directory:** This directory has two purposes. First, it signals
  **where the root of the project is**. This allows constructing paths relative
  to the root of the project, and also running Tuist commands from any directory
  within the project. Second, it's the container for the following files:
  - **ProjectDescriptionHelpers:** This directory contains Swift code that's
    shared across all the manifest files. Manifest files can `import
    ProjectDescriptionHelpers` to use the code defined in this directory.
    Sharing code is useful to avoid duplications and ensure consistency across
    the projects.
  - **Package.swift:** This file contains Swift Package dependencies for Tuist
    to integrate them using Xcode projects and targets (like
    [CocoaPods](https://cococapods)) that are configurable and optimizable.
    Learn more
    <LocalizedLink href="/guides/features/projects/dependencies">here</LocalizedLink>.

- **Root directory**: The root directory of your project that also contains the
  `Tuist` directory.
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
